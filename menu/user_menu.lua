local http_system = require 'http_system'

local m = {} 

m[#m+1] = {
   href = "/user_dashboard",
   file = "user/dashboard.html",
   name = "Dashboard",
   handler = http_system.generic_page_handler,
   icon = "fas fa-chart-area"
}

m[#m+1] = {
   href = "/user_temperature",
   file = "user/temperature.html",
   name = "Temperature",
   handler = http_system.generic_page_handler,
   icon = "fas fa-chart-area"
}

m[#m+1] = {
   href = "/user_power",
   file = "user/power.html",
   name = "Power",
   handler = http_system.generic_page_handler,
   icon = "fas fa-chart-area"
}

m[#m+1] = {
   href = "/user_vaisala",
   file = "user/vaisala.html",
   name = "Vaisala",
   handler = http_system.generic_page_handler,
   icon = "fas fa-chart-area"
}

m[#m+1] = {
   href = "/user_water",
   file = "user/water.html",
   name = "Water",
   handler = http_system.generic_page_handler,
   icon = "fas fa-chart-area"
}

m[#m+1] = {
   href = "/user_actions",
   file = "user/actions.html",
   name = "Actions",
   handler = http_system.generic_page_handler,
   icon = "fas fa-sliders-h"
}

m[#m+1] = {
   href = "/user_iframe",
   file = "user/iframe.html",
   name = nil,
   handler = http_system.generic_page_handler,
   icon = "fas fa-database"
}


m[#m+1] = {
   href = "/#",
   file = nil,
   name = "———————",
   handler = nil
}


m[#m+1] = {
   href = "/user_iframe?address=http://192.168.1.111/",
   file = nil,
   name = "WirenBoard",
   handler = nil,
   icon = "fas fa-arrow-circle-right"
}

m[#m+1] = {
   href = "/user_iframe?address=http://192.168.1.45:9000/",
   file = nil,
   name = "Portainer",
   handler = nil,
   icon = "fas fa-arrow-circle-right"
}

m[#m+1] = {
   href = "/user_iframe?address=http://st.linergo.ru/login.xhtml",
   file = nil,
   name = 'Linergo',
   handler = nil,
   icon = "fas fa-arrow-circle-right"
}

m[#m+1] = {
   href = "/user_iframe?address=http://gascloud.ru/",
   file = nil,
   name = "GasCloud",
   handler = nil,
   icon = "fas fa-arrow-circle-right"
}

m[#m+1] = {
   href = "/user_iframe?address=http://unilight.su/",
   file = nil,
   name = "Unilight",
   handler = nil,
   icon = "fas fa-arrow-circle-right"
}

m[#m+1] = {
   href = "/user_iframe?address=https://www.m2mconnect.ru/Account/Login",
   file = nil,
   name = "M2M Connect",
   handler = nil,
   icon = "fas fa-arrow-circle-right"
}

return m
