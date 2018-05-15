var action_button_xhr = new XMLHttpRequest();
var action_last_button_object;
var action_endpoint;
var action_button_class;

function action_result() {
    if (action_button_xhr.readyState == 4) {
        if (action_button_xhr.status == 200) {
            var json_data = JSON.parse(action_button_xhr.responseText);
            if (json_data.result == true)
                button_color(action_last_button_object, "success")
            else
                button_color(action_last_button_object, "danger")
        } else
            button_color(action_last_button_object, "danger")
    }
}

function send_action() {
    action_button_xhr.open('POST', action_endpoint + '?action=' + $(this).attr('action-button'), true);
    action_button_xhr.send()
    action_last_button_object = $(this)
    button_color(action_last_button_object, "warning")
}

function button_action_init(endpoint, button_class) {
    action_endpoint = endpoint;
    action_button_class = button_class;
    $("." + action_button_class).on('click', send_action);
    action_button_xhr.onreadystatechange = action_result
}