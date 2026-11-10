# LANScreenShare — трансляция экрана Windows

Скачать файлы и запустить режим через интернет с помощью PowerShell:

    $d=Join-Path $env:TEMP 'LANScreenShare'; New-Item -ItemType Directory -Force -Path $d | Out-Null; $z=Join-Path $d 'source.zip'; Invoke-WebRequest 'https://github.com/whoiyou666-glitch/LANScreenShare/archive/refs/heads/main.zip' -OutFile $z; Expand-Archive $z -DestinationPath $d -Force; & (Join-Path $d 'LANScreenShare-main\Start-Internet.cmd')

Для режима из любой точки мира:
1. Установите Tailscale на оба компьютера: https://tailscale.com/download/windows
2. Подключите оба компьютера к одному защищённому tailnet.
3. На компьютере, экран которого нужно смотреть, выполните команду выше или запустите Start-Internet.cmd.
4. Скопируйте адрес вида http://100.x.y.z:8765/ с экрана первого компьютера.
5. На втором компьютере откройте этот адрес в браузере и введите код, показанный на первом.
6. Если соединение блокируется, на первом компьютере запустите Allow-Tailscale-Firewall.cmd от имени администратора.
7. Чтобы остановить трансляцию, закройте окно PowerShell или нажмите Ctrl+C.

Start.cmd — трансляция только внутри локальной сети. Не открывайте порт 8765 в интернет на роутере.

Программа только показывает экран. Управления мышью/клавиатурой, доступа к файлам, скрытого запуска, службы и автозапуска нет. Пока трансляция запущена, человек с кодом видит все мониторы, включая личные данные. Код меняется при каждом запуске.

**Ограничения:** примерно один кадр в секунду, без звука. На настоящей Windows эта версия ещё не протестирована.
