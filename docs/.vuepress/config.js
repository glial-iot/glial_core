module.exports = {
   themeConfig: {
      nav: [
         {
            text: 'Основная информация', items: [
               { text: 'Что такое GLUE', link: '/what_glue.html' },
               { text: 'Запуск системы', link: '/start.html' },
               { text: 'Скрипты и драйвера', link: '/scripts_and_drivers.html' },
               { text: 'Система логов', link: '/logs.html' },
               { text: 'Общая шина', link: '/bus.html' }
            ]
         },
         {
            text: 'Документация', items: [
               { text: 'Панель управления', link: '/panel.html' },
               { text: 'Руководство разработчика', link: '/developers.html' },
               { text: 'Внутренности системы', link: '/inside.html' }
            ]
         },
         {
            text: 'Примеры', items: [
               { text: 'Драйвера', link: '/examples_driver.html' },
               { text: 'Bus-event скрипты', link: '/examples_bus_event.html' },
               { text: 'Web-event скрипты', link: '/examples_web_event.html' },
               { text: 'Timer-event скрипты', link: '/examples_timer_event.html' },
               { text: 'Shedule-event скрипты', link: '/examples_shedsule_event.html' }
            ]
         }
      ],
      sidebar: "auto",
      displayAllHeaders: true,
      logo: '/logo.png'
   }
}




