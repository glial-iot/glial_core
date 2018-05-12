local driver = {}
driver.name = "fake_off_driver"
driver.active = true
driver.driver_function = function()
a()
end
return driver
