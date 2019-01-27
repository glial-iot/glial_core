-- The generated script is filled with the default content --

masks = {"/test/1", "/test/2"}

local function main()
    while true do
        print("Test driver loop")
        fiber.sleep(600)
    end
end

function init()
    store.fiber_object = fiber.create(main)
end

function destroy()
    if (store.fiber_object:status() ~= "dead") then
        store.fiber_object:cancel()
    end
end

function topic_update_callback(value, topic)
    print("Test driver callback:", value, topic)
end