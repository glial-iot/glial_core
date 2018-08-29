# Что такое Glue?
**Glue** - это каркас для создания систем управления IoT-устройствами, позволяющий обеспечить взаимодействие устройств, использующих различные протоколы и стандарты.

###Glue включает в себя:

- **механизм драйверов**, которые обеспечивают конвертацию приходящих от устройств данных в единый формат

- **механизм скриптов**, позволяющих обрабатывать данные с устройств и создавать логику верхнего уровня для определения того, как эти устройства будут работать вместе.

- **общую шину данных (bus)** для хранения последнего значения каждого параметра с каждого подключенного устройства.

- **драйвера для различных TSDB** позволяют сохранить данные в виде временных рядов (временных последовательностей) для сбора статистики и последующего анализа.

- **систему логгирования** для хранения и отображения событий, ошибок и предупреждений.

# Специфика IoT
Устройства интернета вещей — весьма различны в своих возможностях и характеристиках. Из-за физических ограничений они оперируют множеством протоколов и стандартов: modbus, ethernet, knx, 6lowpan, zigbee, LoRa, и многими другими. 

Принять какой-либо стандарт в качестве единого невозможно, так как на данном этапе развития технологий невозможно обеспечить избыточность в стандарте, достаточную для удовлетворения всех задач одновременно: кому-то необходима высокая скорость связи и mesh-сеть, кому-то большая дальность, в каких-то условиях вообще невозможно использовать радио-протоколы.

Таким образом, текущая ситуация в современном интернете вещей заключается в том, что у нас есть множество стандартов передачи данных, и решения этой проблемы в ближайшие годы не предвидится.

## Чем Glue не является?
- Генератором красивых веб-панелей управления
- Графическим конфигуратором
- Панелью управления умным домом
- Средством настройки для устройств, которые производим мы
- Генератором прошивок для Arduino
- Монструозной системой, на обучение которой надо потратить месяц
- Закрытой вендорским продуктом с принципом "что дали тем и пользуйтесь"
- Системой с готовым набором драйверов и скриптов на все случаи жизни

## Тогда что такое Glue?
- Система, ориентированная на разработчиков: предполагается, что писать код вам привычнее, чем расставлять курсором элементы
- Система, ориентированная на простоту разработки: по нашему мнению, разработчик логики не должен вникать в работу системы на низком уровне.
- Системой с открытом кодом: Glue(а так же Tarantool и Lua, которые лежат в его основе) имеют открытый код, что позволяет легко предлагать и дописывать новый функционал.

## Режимы работы Glue  
Glue может работать в нескольких режимах.  

В режиме IMPACT все данные, поступающие с драйверов хранятся в облачном хранилище [Nokia IMPACT](https://networks.nokia.com/solutions/iot-platform) 
![режим IMPACT](docs/images/glueImpactMode.png "режим IMPACT")  

В режиме Non-IMPACT, все данные хранятся в локальном key-value хранилище на базе платформы Tarantool.  

![режим Non-IMPACT](docs/images/glueNonImpact.png "режим Non-IMPACT")   


# Состав системы  

## Компоненты системы  

Стандартный пакет установки Glue включает в себя 
- серверную часть ([сервис Glue](https://github.com/vvzvlad/glue) ), написанную на Lua с использованием платформы Tarantool, осуществляющую получение/сбор, хранение и обработку входящих данных (приведение в единый вид)
- клиентскую часть - панель управления ([Glue Panel](https://github.com/vvzvlad/glue_panel)), обеспечивающую визуализацию данных, создание/редактирование драйверов и скриптов и управление сервисом Glue 

## Панель управления 

Панель управления Glue включает в себя:
- таблицу данных, поступающих на шину (Bus) от различных устройств
- список логов, поступающих из различных скриптов и драйверов
- редактор драйверов
- редактор пользовательских скриптов (web-event scripts, bus-event scripts, ...)
- страница с настройками

![Настройки Glue](docs/images/managePanel.png "Настройки Glue")  

На странице с настройками можно 
- выбрать сервер, с которым будет работать панель
- выбрать TSDB, в которую будет происходить экспорт данных
- перезапустить сервис Glue
- обновить и перезапустить сервис Glue (?)
- удалить все данные из шины Bus
- очистить все хранилище данных и остановить сервис Glue
 

## Drivers
Драйвера — это скрипты на lua, которые реализуют тот или иной протокол(часто с привлечением сторонних библиотек) для связи с устройством, конвертируя данные приходящие с каждого устройства в единый формат. Они работают в качестве транслятора между "языком" устройства и "языком" общей шины. 

Драйвера хранятся во NoSQL хранилище Tarantool.  
Используя встроенный в Glue Panel редактор скриптов, вы можете создавать, тестировать и запускать практически любые скрипты драйверов на языке Lua.

![Список драйверов](docs/images/driversList.png "Список драйверов")

Скрипты можно создавать, редактировать, включать/отключать, перезапускать и удалять.

![Редактирование скриптов драйвера](docs/images/driverEdit.png "Редактирование скриптов драйвера")

В процсессе создания или рекдактирования пользовательских скриптов (драйверы, bus-event scripts, web-event scripts), доступны:  
- внутренние переменные
- функции логгирования
- функции для работы с шиной (Bus)

###Внутренние переменные скрипта
**script_name** - перменная, содержащая название текущего скрипта  
**_script_uuid** -  переменная, содержащая uuid (уникальный идентификатор) текущего скрипта  
**store** - таблица для хранения временных данных, уникальная для каждого скрипта.  Ее можно использовать просто как переменную:  
```lua
store.value = 5 
print(store.value) -- 5
```

###Функции для работы с логами

**log_info()** - добавляет в лог запись уровня "INFO"  
**log_warning()** - добавляет в лог запись уровня "WARNING"  
**log_error()** - добавляет в лог запись уровня "ERROR"  
**log_user()** - добавляет в лог запись уровня "USER"  
**log()** - аналогично функции log_user()  
**print()** - аналогично функции log_user()   

###Функции для работы с шиной (Bus)

**update_value(topic, value)**: Обновляет тему "topic", устанавливая значение "value"   
**shadow_update_value(topic, value)**: Обновляет тему "topic", устанавливая значение "value", но не запускает event-скрипты, которые прикреплены к этой теме.  
**get_value(topic)**: Получает значение темы "topic"  
**bus_serialize(pattern)**: Получает содержимое шины (bus) в виде таблицы. Если передана переменная "pattern", то будет выбрана только часть таблицы, соответствующая заданному шаблону.  

Данные, поступающие в драйвер могут обновлять значение темы "topic" в стандартном (standard) или теневом (shadow) режиме. В первом случае, отработают все скрипты, которые прослушивают изменения значения, во втором случае, значение будет изменено без запуска скриптов.

![Обновление данных шины](docs/images/glueBusUpdate.png "Обновление данных шины")


## Bus  

Общая шина — это быстрая in-memory база данных ключ:значение, в которой ключом является стандартизованный адрес устройства или датчика, а значением — последние данные с этого устройства или датчика.

![Шина](docs/images/busList.png "Шина")

Данные, поступающие от драйверов в шину обновляются с интервалом, заданным пользователем (от 0.5 до 5 сек). Существует и возможность приостановить обновление данных.

Данные могут быть представлены в виде списка или древовидной иерархии, генерируемой на основе названия источника данных ("topic").

Запись значений в TSDB (time-series database) можно включать и отключать индивидуально для каждого источника. В качестве TSDB может использоваться  [InfluxData (InfluxDB)](https://www.influxdata.com/) или [Nokia IMPACT](https://networks.nokia.com/solutions/iot-platform).  

![Настройки TSDB](docs/images/managePanel.png "Настройки TSDB")  

Выбрать TSDB для экспорта данных можно на странице настроек (пункт Manage в левом боковом меню).

## Scripts  

Скрипты — это обособленные части кода, которые реализуют прикладную логику: расчет, изменение, реакции, выдача данных.  
Скрипты бывают нескольких видов: 
- **bus-event**
- **timer-event** 
- **web-event**

### Bus-event scripts  

Этот тип скриптов выполняется для каждого устройства из группы устройств, определяемых маской, при обновлении их данных на шине (Bus).
![Bus-event scripts](docs/images/busEventScriptList.png "Bus-event scripts")

При создании скрипта, необходимо использовать функцию **event_handler()**, в которую можно передать значение "value" и источник "topic" соответствующего события на шине.  

```lua
function event_handler(value, topic)
   -- Ваш код здесь
end
```  

Пример кода, который прослушивает изменение показаний концентрации угарного газа CO на климатической станции и обновляет значение приращения этого значения для отслеживания динамики:  

```lua
function event_handler(value)
   store.old_value = store.old_value or 0
   difference =  value - store.old_value
   update_value("/wb/AN4SSJFL/vaisala/26651/CO_d", difference)

   store.old_value = value
end
```  

![Bus-event script](docs/images/busEventScript.png "Bus-event script")  

<!-- ### Timer-event scripts
Таймер - каждые N минут например (или через столько-то минут?)

Scheduled - запланированное время в формате HH:mm или DD:HH:MM ? (1 раз или солько?) -->

### Web-event scripts

Скрипты, выполняемые при обращении к выбранному URL ("endpoint") с помощью HTTP запроса.  

![Web-event scripts](docs/images/webScriptsList.png "Web-event scripts") 

Функция, реализующая непосредственную логику при обработке запроса - **http_callback()**.

В скриптах доступны переменные, содержащие данные запроса: 
- **params** - массив с параметрами запроса
- **req** - объект запроса [HTTP сервера Tarantool](https://github.com/tarantool/http)  

![Web-event script](docs/images/webScript.png "Web-event script") 

```lua
function http_callback(params, req)
   -- Ваш код здесь
end
```  

Пример скрипта, который сериализует в json выборку данных из шины по маске _"/openweathermap/0/weatherstation"_ и отдает по HTTP при обращении:  

```lua
function http_callback(params)
   local data = bus_serialize("/openweathermap/0/weatherstation")
   return data.openweathermap["0"].weatherstation
end
```  

В результате обращения к URL _/we/weather_stations_, что соответствует endpoint'у "weather_stations", получаем данные, сериализованные в json:  

![Web-event script](docs/images/webScriptResponse.png "Web-event script") 
