# One-command, visible, temporary screen sharing via Cloudflare Quick Tunnel.
# No admin rights, permanent installer, Tailscale, inbound firewall rule, or autorun.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows 10/11 required.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw '64-bit Windows required.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Write-Host ''
Write-Host 'LAN Screen Share / Internet' -ForegroundColor Cyan
Write-Host 'The entire screen will be visible to anyone you give the private link.' -ForegroundColor Yellow
Write-Host 'This session stops when you press Enter or close PowerShell.' -ForegroundColor Yellow
Write-Host ''

$dir = Join-Path $env:LOCALAPPDATA 'LANScreenShare'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cloudflared = Join-Path $dir 'cloudflared-2026.10.7-windows-amd64.exe'
$expectedHash = 'd521b3bf68982165f0d06d76732f22d9a105ef057ff3ae4c0986f3a23190950f'
$cloudflaredUrl = 'https://github.com/cloudflare/cloudflared/releases/download/2026.10.7/cloudflared-windows-amd64.exe'
$serverScript = Join-Path $dir 'Start-ScreenShare.ps1'
$serverUrl = 'https://raw.githubusercontent.com/whoiyou666-glitch/LANScreenShare/main/Start-ScreenShare.ps1'
$tunnel = $null
try {
  if (-not (Test-Path $cloudflared) -or (Get-FileHash -LiteralPath $cloudflared -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    Write-Host 'Downloading official Cloudflare tunnel (one-time, ~20 MB)...'
    $tmp = "$cloudflared.download"
    Invoke-WebRequest -Uri $cloudflaredUrl -OutFile $tmp -UseBasicParsing
    $hash=(Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $expectedHash) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      throw "Cloudflare download hash mismatch; expected $expectedHash, got $hash"
    }
    Move-Item -LiteralPath $tmp -Destination $cloudflared -Force
  }
  Write-Host 'Downloading the screen-sharing app from your GitHub...'
  Invoke-WebRequest -Uri $serverUrl -OutFile $serverScript -UseBasicParsing

  # Bind the local server only to 127.0.0.1, never to the router / public network.
  $freePort = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0)
  $freePort.Start()
  try { $port = ([System.Net.IPEndPoint]$freePort.LocalEndpoint).Port }
  finally { $freePort.Stop() }

  $sessionId = [guid]::NewGuid().ToString('N')
  $stderr = Join-Path $dir "tunnel-$sessionId.stderr.log"
  $stdout = Join-Path $dir "tunnel-$sessionId.stdout.log"
  Write-Host 'Creating a temporary HTTPS link...'
  $tunnel = Start-Process -FilePath $cloudflared -ArgumentList @('tunnel','--no-autoupdate','--url',"http://127.0.0.1:$port") -WindowStyle Hidden -PassThru -RedirectStandardError $stderr -RedirectStandardOutput $stdout
  $url = $null
  for ($i=0; $i -lt 180; $i++) {
    if ($tunnel.HasExited) {
      $logs=Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
      throw "Cloudflare tunnel stopped unexpectedly. Details: $logs"
    }
    $logs=Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
    if ($logs -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $url = $Matches[0]; break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $url) {
    throw "Cloudflare did not provide a link. Check your Internet connection. Logs: $stderr"
  }
  # The script displays a new 128-bit one-time access token as part of the share URL.
  Write-Host ''
  Write-Host 'Starting live screen sharing now...' -ForegroundColor Cyan
  & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $serverScript -Port $port -LocalOnly -PublicUrl $url
  if ($LASTEXITCODE -ne 0) { throw "Screen-sharing server exited with code $LASTEXITCODE" }
}
finally {
  if ($null -ne $tunnel) {
    try { if (-not $tunnel.HasExited) { $tunnel.Kill(); $tunnel.WaitForExit(3000) | Out-Null } }
    catch { Write-Warning "Could not terminate tunnel: $_" }
  }
  Write-Host 'Sharing session ended.' -ForegroundColor Yellow
}
