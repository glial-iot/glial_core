var last_delete_address = "";

function edit_button_action(event) {
    location.href = '/system_webedit_edit?address=' + $(this).attr('address')
}

function new_button_action() {
    let this_button = $(this)
    let script_type = this_button.attr('id')
    let script_filename = $("#" + this_button.attr('filename-id'))["0"].value

    if (script_type == undefined || script_filename == undefined)
        return

    let filedir
    let filetype
    let xhr_new_action = new XMLHttpRequest();
    if (script_type == "new_driver") {
        filedir = "drivers"
        filetype = ".lua"
    }
    if (script_type == "new_webevent") {
        filedir = "webevents"
        filetype = ".lua"
    }
    if (script_type == "new_event") {
        filedir = "events"
        filetype = ".lua"
    }
    if (script_type == "new_timer_event") {
        filedir = "timerevents"
        filetype = ".lua"
    }
    if (script_type == "new_user_html") {
        filedir = "templates/user"
        filetype = ".html"
    }

    let address = 'system_webedit_data?item=new&address=' + filedir + "/" + script_filename + filetype
    xhr_new_action.open('POST', address, true);
    xhr_new_action.send()
    setTimeout(function(event) {
        location.href = location.href
    }, 500);
}

function delete_button_action(event) {
    if (last_delete_address == $(this).attr('address')) {
        var xhr_delete_action = new XMLHttpRequest();
        xhr_delete_action.open('POST', 'system_webedit_data?item=delete&address=' + $(this).attr('address'), true);
        xhr_delete_action.send()
        button_color($(this), "light")
        setTimeout(function(event) {
            location.href = location.href
        }, 500);
    } else {
        button_color($(this), "danger")
        last_delete_address = $(this).attr('address')
        setTimeout(function(event) {
            last_delete_address = "";
            button_color($('.button_delete_sub_class'), "warning")
        }, 1000);
    }
}

function bind_table_button_actions() {
    $('.button_edit_sub_class').on('click', edit_button_action);
    $('.button_delete_sub_class').on('click', delete_button_action);
    $('.button_new_sub_class').on('click', new_button_action);
}

function render_scripts_table(table_name, address, callback) {
    var xhr_scripts_list = new XMLHttpRequest();

    function update_scripts_list_callback() {
        if (xhr_scripts_list.readyState == 4 && xhr_scripts_list.status == 200) {
            var json_data = JSON.parse(xhr_scripts_list.responseText);
            if (json_data.none_data != "true") {
                clear_table(table_name)
                add_row_table(table_name, "head", ["Filename", /* "active", */ "", ""], undefined, [70, /* 30, */ 10, 10])
                for (let index = 0; index < json_data.length; index++) {
                    var button_edit_html = '<button type="button" address="' + json_data[index].address + '" class="btn btn-block btn-sm btn-info button_edit_sub_class"><i class="fas fa-edit"></i> Edit</button>'
                    var button_delete_html = '<button type="button" address="' + json_data[index].address + '" class="btn btn-block btn-sm btn-warning button_delete_sub_class"><i class="fas fa-edit"></i> Move to trash</button>'
                    add_row_table(table_name, "body", [json_data[index].name, /* json_data[index].active, */ button_edit_html, button_delete_html])
                }
                if (callback != undefined)
                    callback();
            }
        }
    }

    xhr_scripts_list.onreadystatechange = update_scripts_list_callback
    xhr_scripts_list.open('POST', 'system_webedit_data?item=get_list&address=' + address, true);
    xhr_scripts_list.send()
}