curl -fsSL https://raw.githubusercontent.com/88Dand/TransdetalTabloEmulator/main/EmulatorInstall.sh | bash

Что делает команда
скачивает EmulatorInstall.sh напрямую из GitHub Raw
сразу передаёт его в bash
устанавливает сервис
запускает systemd unit

Скрипт устанавливает на сервер с ubuntu эмулятор табло и разворачивает службу на поту 8090
