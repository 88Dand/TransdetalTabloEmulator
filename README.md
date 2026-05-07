curl -fsSL https://raw.githubusercontent.com/88Dand/TransdetalTabloEmulator/main/EmulatorInstall.sh | bash

Что делает команда
скачивает EmulatorInstall.sh напрямую из GitHub Raw
сразу передаёт его в bash
устанавливает сервис
запускает systemd unit

Скрипт устанавливает на сервер с ubuntu эмулятор табло и разворачивает службу на поту 8090

Проверка статуса:
systemctl status parking-board

Логи:
journalctl -u parking-board -f

Открыть в браузере:
http://SERVER_IP:8090
