HTMLTableRowElement.prototype.insertCell = (function(oldInsertCell) {
    return function(index) {
        if (this.parentElement.tagName.toUpperCase() == "THEAD") {
            if (index < -1 || index > this.cells.length) {} else {
                let th = document.createElement("TH");
                if (arguments.length == 0 || index == -1 || index == this.cells.length)
                    return this.appendChild(th);
                else
                    return this.insertBefore(th, this.children[index]);
            }
        }
        return oldInsertCell.apply(this, arguments);
    }
})(HTMLTableRowElement.prototype.insertCell);


function add_row_table(table_name, type, table_data, custom_class, table_custom_width) {
    var table_current_row;
    if (type == "head")
        table_current_row = document.getElementById(table_name).createTHead().insertRow(-1);
    else {
        if (document.getElementById(table_name).tBodies.length == 0)
            table_current_row = document.getElementById(table_name).createTBody().insertRow(-1);
        else
            table_current_row = document.getElementById(table_name).tBodies[0].insertRow(-1);
    }
    for (var j = 0; j < table_data.length; j++) {
        var table_current_cell = table_current_row.insertCell(-1)
        table_current_cell.innerHTML = table_data[j];
        if (custom_class != undefined)
            table_current_cell.classList.add(custom_class);
        if (table_custom_width != undefined)
            table_current_cell.style = "width: " + table_custom_width[j] + "%";
    }
}

function clear_table(table_name) {
    document.getElementById(table_name).innerHTML = "";
}


function render_scripts_table(table_name, address) {
    var xhr_scripts_list = new XMLHttpRequest();

    function update_scripts_list_callback() {
        if (xhr_scripts_list.readyState == 4 && xhr_scripts_list.status == 200) {
            var json_data = JSON.parse(xhr_scripts_list.responseText);
            if (json_data.none_data != "true") {
                //console.log(json_data)
                add_row_table(table_name, "head", ["Filename", /* "active", */ ""], undefined, [80, /* 30, */ 10])
                for (let index = 0; index < json_data.length; index++) {
                    var button_html = '<button type="button" address="' + json_data[index].address + '" class="btn btn-block btn-sm btn-info button_edit_sub_class"><i class="fas fa-edit"></i> Edit</button>'
                    add_row_table(table_name, "body", [json_data[index].name, /* json_data[index].active, */ button_html])
                }
                $('.button_edit_sub_class').on('click', function(event) {
                    location.href = '/webedit_edit?address=' + $(this).attr('address')
                });
            }
        }
    }

    xhr_scripts_list.onreadystatechange = update_scripts_list_callback
    xhr_scripts_list.open('POST', 'webedit?item=get_list&address=' + address, true);
    xhr_scripts_list.send()
}