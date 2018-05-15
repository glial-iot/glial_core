var last_delete_address = "";

function edit_button_action(event) {
    location.href = '/system_webedit_edit?address=' + $(this).attr('address')
}

function new_button_action() {
    var xhr_new_action = new XMLHttpRequest();
    xhr_new_action.open('POST', 'system_webedit_data?item=new&address=' + $('#new_file_form')["0"].value, true);
    xhr_new_action.send()
}

function delete_button_action(event) {
    console.log("action")
    if (last_delete_address == $(this).attr('address')) {
        console.log("light")
        var xhr_delete_action = new XMLHttpRequest();
        xhr_delete_action.open('POST', 'system_webedit_data?item=delete&address=' + $(this).attr('address'), true);
        xhr_delete_action.send()
        button_color($(this), "light")
        setTimeout(function(event) {
            location.href = location.href
        }, 500);
    } else {
        button_color($(this), "danger")
        console.log("danger")
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
                //console.log(json_data)
                clear_table(table_name)
                add_row_table(table_name, "head", ["Filename", /* "active", */ "", ""], undefined, [70, /* 30, */ 10, 10])
                for (let index = 0; index < json_data.length; index++) {
                    var button_edit_html = '<button type="button" address="' + json_data[index].address + '" class="btn btn-block btn-sm btn-info button_edit_sub_class"><i class="fas fa-edit"></i> Edit</button>'
                    var button_delete_html = '<button type="button" address="' + json_data[index].address + '" class="btn btn-block btn-sm btn-warning button_delete_sub_class"><i class="fas fa-edit"></i> Delete</button>'
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