# LAN Screen Share - visible screen sharing, no unattended access.
# Start via Start-Internet.cmd (Tailscale) or Start.cmd (private LAN).
param([ValidateRange(1024,65535)][int]$Port=8765, [switch]$Tailscale, [switch]$LocalOnly, [string]$PublicUrl)
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw "Windows 10/11 required" }
$bind='0.0.0.0'
if ($Tailscale -and $LocalOnly) { throw 'Choose either Tailscale or LocalOnly' }
if ($PublicUrl -and -not $LocalOnly) { throw 'PublicUrl requires LocalOnly' }
if ($LocalOnly) { $bind='127.0.0.1' }
if ($Tailscale) {
  $exe=Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
  if (-not (Test-Path $exe)) { throw 'Install Tailscale first: https://tailscale.com/download/windows' }
  $ips=@(& $exe ip -4 2>$null | Where-Object { $_ -match '^100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}$' })
  if ($LASTEXITCODE -ne 0 -or $ips.Count -eq 0) { throw 'Connect Tailscale and sign in first' }
  $bind=[string]$ips[0]
}
$rng=[System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes=New-Object byte[] 16
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$key=([BitConverter]::ToString($bytes)).Replace('-','')
$html=@'
<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LAN Screen Share</title><style>
body{background:#111827;color:#fafafa;font:16px Arial,sans-serif;margin:30px auto;max-width:1150px;padding:0 18px}
input,button{font:inherit;padding:12px;border-radius:8px;margin:5px;border:1px solid #566276}
input{background:#1f2937;color:white;width:min(420px,85%)}
button{background:#345bdd;color:#fff;cursor:pointer}img{width:100%;border-radius:10px;display:none}
p{color:#cbd5e1}
</style></head><body><h2>LAN Screen Share — просмотр экрана</h2>
<p>Введите код с компьютера, который транслирует экран. Только просмотр, без управления.</p>
<input id="key" type="password" placeholder="Код доступа" autocomplete="off"><button id="go">Подключиться</button><button id="off">Отключиться</button>
<p id="status">Не подключено</p><img id="screen" alt="Экран удалённого компьютера">
<script>
let active=false,url=null;const key=document.getElementById('key'),img=document.getElementById('screen'),status=document.getElementById('status');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function watch(){if(active)return;const code=key.value.trim();if(!code){status.textContent='Введите код';return}
active=true;while(active){try{let r=await fetch('/frame',{method:'POST',headers:{'X-View-Key':code},cache:'no-store'});
if(!r.ok){status.textContent=r.status===401?'Неверный код':'Ошибка '+r.status;break}
let b=await r.blob();if(!active)break;const next=URL.createObjectURL(b);img.src=next;img.style.display='block';if(url)URL.revokeObjectURL(url);url=next;status.textContent='Подключено: только просмотр'
}catch(e){status.textContent='Соединение потеряно';break}await sleep(750)}active=false}
document.getElementById('go').onclick=watch;document.getElementById('off').onclick=()=>{active=false;status.textContent='Отключено'};
key.onkeydown=e=>{if(e.key==='Enter')watch()};
const fromLink=location.hash.substring(1);
if(/^[a-f0-9]{32}$/i.test(fromLink)){key.value=fromLink;watch()}
</script></body></html>
'@
$cs=@'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;
public static class ShareServer {
  static byte[] page;
  static string secret;
  static bool restricted;
  static bool Allowed(IPAddress ip) {
    byte[] b=ip.GetAddressBytes();
    if(b.Length!=4)return IPAddress.IsLoopback(ip);
    if(restricted)return b[0]==100 && b[1]>=64 && b[1]<=127;
    return IPAddress.IsLoopback(ip) || b[0]==10 || (b[0]==172 && b[1]>=16 && b[1]<=31) ||
      (b[0]==192 && b[1]==168) || (b[0]==100 && b[1]>=64 && b[1]<=127);
  }
  static void Reply(NetworkStream stream,int code,string msg,string mime,byte[] body) {
    string h="HTTP/1.1 "+code+" "+msg+"\r\nContent-Type: "+mime+"\r\nContent-Length: "+body.Length+
    "\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n";
    byte[] head=Encoding.ASCII.GetBytes(h);stream.Write(head,0,head.Length);stream.Write(body,0,body.Length);
  }
  static byte[] Text(string s){return Encoding.UTF8.GetBytes(s);}
  static byte[] Capture(){
    Rectangle r=SystemInformation.VirtualScreen;
    if(r.Width<=0||r.Height<=0)throw new Exception("No active screen");
    using(Bitmap b=new Bitmap(r.Width,r.Height,PixelFormat.Format24bppRgb)) {
      using(Graphics g=Graphics.FromImage(b))g.CopyFromScreen(r.Left,r.Top,0,0,r.Size);
      double f=Math.Min(1.0,Math.Min(1600.0/r.Width,900.0/r.Height));
      using(Bitmap outBmp=new Bitmap(Math.Max(1,(int)(r.Width*f)),Math.Max(1,(int)(r.Height*f)))) {
        using(Graphics g=Graphics.FromImage(outBmp))g.DrawImage(b,0,0,outBmp.Width,outBmp.Height);
        using(MemoryStream m=new MemoryStream()) {
          ImageCodecInfo jpeg=null;foreach(ImageCodecInfo c in ImageCodecInfo.GetImageEncoders())if(c.MimeType=="image/jpeg"){jpeg=c;break;}
          if(jpeg==null)throw new Exception("JPEG encoder unavailable");
          using(EncoderParameters p=new EncoderParameters(1)){
            p.Param[0]=new EncoderParameter(System.Drawing.Imaging.Encoder.Quality,70L);
            outBmp.Save(m,jpeg,p);
          }
          return m.ToArray();
        }
      }
    }
  }
  static bool Auth(string s) {
    if(s==null)return false;string v=s.Trim().ToUpperInvariant();
    int diff=v.Length^secret.Length;
    for(int i=0;i<secret.Length;i++)diff|=secret[i]^(i<v.Length?v[i]:0);
    return diff==0;
  }
  static void Handle(TcpClient client) {
    using(client){
      client.ReceiveTimeout=5000;client.SendTimeout=10000;
      using(NetworkStream stream=client.GetStream()){
        if(!Allowed(((IPEndPoint)client.Client.RemoteEndPoint).Address))return;
        using(StreamReader reader=new StreamReader(stream,Encoding.ASCII,false,4096,true)){
          string req=reader.ReadLine();if(String.IsNullOrEmpty(req))return;
          string[] bits=req.Split(' ');if(bits.Length<2)return;
          string supplied=null;int total=req.Length;
          for(int i=0;i<100;i++){
            string line=reader.ReadLine();if(String.IsNullOrEmpty(line))break;
            total+=line.Length;if(total>16000)return;
            int at=line.IndexOf(':');
            if(at>0&&line.Substring(0,at).Trim().Equals("X-View-Key",StringComparison.OrdinalIgnoreCase))
              supplied=line.Substring(at+1).Trim();
          }
          if(bits[0]=="GET"&&(bits[1]=="/"||bits[1]=="/index.html"))Reply(stream,200,"OK","text/html; charset=utf-8",page);
          else if(bits[0]=="POST"&&bits[1]=="/frame"){
            if(!Auth(supplied)){Reply(stream,401,"Unauthorized","text/plain",Text("Invalid code"));return;}
            Console.WriteLine("[VIEWER] Screen frame requested");
            try { Reply(stream,200,"OK","image/jpeg",Capture()); }
            catch(Exception e){Reply(stream,503,"Unavailable","text/plain",Text("Capture failed: "+e.Message));}
          }else Reply(stream,404,"Not Found","text/plain",Text("Not found"));
        }
      }
    }
  }
  static TcpListener server;
  static volatile bool running;
  public static void Start(int port,string address,string html,string key,bool tailscale) {
    restricted=tailscale;secret=key;page=Encoding.UTF8.GetBytes(html);
    server=new TcpListener(IPAddress.Parse(address),port);server.Start(10);running=true;
    System.Threading.Thread worker=new System.Threading.Thread(delegate() {
      try{
        while(running){
          TcpClient c;
          try { c=server.AcceptTcpClient(); }
          catch(SocketException){break;}
          catch(ObjectDisposedException){break;}
          try{Handle(c);}catch(Exception e){Console.WriteLine("Request error: "+e.Message);c.Close();}
        }
      }finally{Console.WriteLine("Screen sharing stopped.");}
    });
    worker.IsBackground=true;
    worker.Start();
  }
  public static void Stop(){running=false;if(server!=null)server.Stop();}
}

'@
Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.Drawing','System.Windows.Forms') -ErrorAction Stop
Write-Host ''
Write-Host 'LAN SCREEN SHARE - VISIBLE SCREEN SHARING' -ForegroundColor Cyan
Write-Host 'WARNING: Viewer with the code can see ALL monitors and private information.' -ForegroundColor Yellow
if ($PublicUrl) {
  $safeUrl=$PublicUrl.TrimEnd('/')
  Write-Host ("VIEW LINK (secret - share only with trusted people): {0}/#{1}" -f $safeUrl,$key) -ForegroundColor Green
} elseif ($Tailscale) {
  Write-Host ("URL for other Tailscale computer: http://{0}:{1}/" -f $bind,$Port) -ForegroundColor Green
} else {
  Write-Host 'LAN mode: use this PC private IP address and port ' $Port
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -match '^(10\.|172\.|192\.168\.)'} | ForEach-Object { Write-Host ("http://{0}:{1}/" -f $_.IPAddress,$Port) }
}
Write-Host "ACCESS CODE: $key" -ForegroundColor Green
Write-Host 'STOP: press Ctrl+C or close this terminal.' -ForegroundColor Yellow
Write-Host 'No autostart, no remote control, no audio.'
[ShareServer]::Start($Port,$bind,$html,$key,[bool]$Tailscale)
try {
  [void](Read-Host 'SCREEN SHARING ACTIVE. Press ENTER to STOP')
} finally {
  [ShareServer]::Stop()
}
