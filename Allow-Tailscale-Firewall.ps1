# Run as Administrator on the screen-sharing PC only.
param([ValidateRange(1024,65535)][int]$Port=8765,[switch]$Remove)
$ErrorActionPreference='Stop'
$name="LAN Screen Share (Tailscale port $Port)"
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as Administrator' }
if ($Remove) {
  Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  Write-Host "Firewall rule removed";exit 0
}
$exe=Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (-not (Test-Path $exe)) { throw 'Tailscale must be installed and connected first' }
$ips=@(& $exe ip -4 2>$null | Where-Object { $_ -match '^100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}$' })
if ($LASTEXITCODE -ne 0 -or $ips.Count -eq 0) { throw 'Connect Tailscale first' }
Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -LocalAddress $ips[0] -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
Write-Host "Allowed TCP $Port on Tailscale address $($ips[0]) only."
Write-Host "To remove: run this script with -Remove as Administrator."
