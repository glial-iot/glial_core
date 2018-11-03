function init()

    local initial_table = {foo = "bar", bar = 123, foobar=true}
    update_value("/test/test_deepcopy/initial_table/foo", initial_table.foo)
    update_value("/test/test_deepcopy/initial_table/bar", initial_table.bar)
    update_value("/test/test_deepcopy/initial_table/foobar", initial_table.foobar)

    local copied_table = deepcopy(initial_table)
    copied_table.foo = "new"
    copied_table.bar = 321
    copied_table.foobar = false

    update_value("/test/test_deepcopy/initial_table_not_modified/foo", initial_table.foo)
    update_value("/test/test_deepcopy/initial_table_not_modified/bar", initial_table.bar)
    update_value("/test/test_deepcopy/initial_table_not_modified/foobar", initial_table.foobar)

    update_value("/test/test_deepcopy/copied_table_modified/foo", copied_table.foo)
    update_value("/test/test_deepcopy/copied_table_modified/bar", copied_table.bar)
    update_value("/test/test_deepcopy/copied_table_modified/foobar", copied_table.foobar)

end

function destroy()

end
