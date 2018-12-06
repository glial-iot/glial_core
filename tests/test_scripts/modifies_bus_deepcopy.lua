function init()

    local initial_table = {foo = "bar", bar = 123, foobar=true}
    update({topic = "/test/test_deepcopy/initial_table/foo", value = initial_table.foo})
    update({topic = "/test/test_deepcopy/initial_table/bar", value = initial_table.bar})
    update({topic = "/test/test_deepcopy/initial_table/foobar", value = initial_table.foobar})

    local copied_table = deepcopy(initial_table)
    copied_table.foo = "new"
    copied_table.bar = 321
    copied_table.foobar = false

    update({topic = "/test/test_deepcopy/initial_table_not_modified/foo", value = initial_table.foo})
    update({topic = "/test/test_deepcopy/initial_table_not_modified/bar", value = initial_table.bar})
    update({topic = "/test/test_deepcopy/initial_table_not_modified/foobar", value = initial_table.foobar})

    update({topic = "/test/test_deepcopy/copied_table_modified/foo", value = copied_table.foo})
    update({topic = "/test/test_deepcopy/copied_table_modified/bar", value = copied_table.bar})
    update({topic = "/test/test_deepcopy/copied_table_modified/foobar", value = copied_table.foobar})

end

function destroy()

end
