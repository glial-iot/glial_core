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



var Base64 = { _keyStr: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=", encode: function(e) { var t = ""; var n, r, i, s, o, u, a; var f = 0;
        e = Base64._utf8_encode(e); while (f < e.length) { n = e.charCodeAt(f++);
            r = e.charCodeAt(f++);
            i = e.charCodeAt(f++);
            s = n >> 2;
            o = (n & 3) << 4 | r >> 4;
            u = (r & 15) << 2 | i >> 6;
            a = i & 63; if (isNaN(r)) { u = a = 64 } else if (isNaN(i)) { a = 64 }
            t = t + this._keyStr.charAt(s) + this._keyStr.charAt(o) + this._keyStr.charAt(u) + this._keyStr.charAt(a) } return t }, decode: function(e) { var t = ""; var n, r, i; var s, o, u, a; var f = 0;
        e = e.replace(/[^A-Za-z0-9\+\/\=]/g, ""); while (f < e.length) { s = this._keyStr.indexOf(e.charAt(f++));
            o = this._keyStr.indexOf(e.charAt(f++));
            u = this._keyStr.indexOf(e.charAt(f++));
            a = this._keyStr.indexOf(e.charAt(f++));
            n = s << 2 | o >> 4;
            r = (o & 15) << 4 | u >> 2;
            i = (u & 3) << 6 | a;
            t = t + String.fromCharCode(n); if (u != 64) { t = t + String.fromCharCode(r) } if (a != 64) { t = t + String.fromCharCode(i) } }
        t = Base64._utf8_decode(t); return t }, _utf8_encode: function(e) { e = e.replace(/\r\n/g, "\n"); var t = ""; for (var n = 0; n < e.length; n++) { var r = e.charCodeAt(n); if (r < 128) { t += String.fromCharCode(r) } else if (r > 127 && r < 2048) { t += String.fromCharCode(r >> 6 | 192);
                t += String.fromCharCode(r & 63 | 128) } else { t += String.fromCharCode(r >> 12 | 224);
                t += String.fromCharCode(r >> 6 & 63 | 128);
                t += String.fromCharCode(r & 63 | 128) } } return t }, _utf8_decode: function(e) { var t = ""; var n = 0; var r = c1 = c2 = 0; while (n < e.length) { r = e.charCodeAt(n); if (r < 128) { t += String.fromCharCode(r);
                n++ } else if (r > 191 && r < 224) { c2 = e.charCodeAt(n + 1);
                t += String.fromCharCode((r & 31) << 6 | c2 & 63);
                n += 2 } else { c2 = e.charCodeAt(n + 1);
                c3 = e.charCodeAt(n + 2);
                t += String.fromCharCode((r & 15) << 12 | (c2 & 63) << 6 | c3 & 63);
                n += 3 } } return t } }


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
                    location.href = '/system_webedit_edit?address=' + $(this).attr('address')
                });
            }
        }
    }

    xhr_scripts_list.onreadystatechange = update_scripts_list_callback
    xhr_scripts_list.open('POST', 'system_webedit_data?item=get_list&address=' + address, true);
    xhr_scripts_list.send()
}