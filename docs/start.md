# Старт системы

## Как запустить Glue?

1. Установите [Tarantool](https://www.tarantool.io/en/download/) >1.9
1. Клонируйте репозиторий: ```git clone https://github.com/vvzvlad/glue.git && cd glue```
1. Установите дополнительные пакеты(для пакета mqtt нужен libmosquitto-dev): ```tarantoolctl rocks install http && tarantoolctl rocks install mqtt && tarantoolctl rocks install dump && tarantoolctl rocks install cron-parser```
1. Запустите серверную часть: ```./cycle_glue.sh``` (запустится HTTP сервер на порту 8080)
1. Установите и запустите панель управления [Glue Webapp](https://github.com/vvzvlad/glue_web_app)
1. При необходимости, укажите адрес HTTP сервера на странице настроек в панели управления, если он отличается от localhost:8080

