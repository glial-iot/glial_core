function button_color(button_object, new_class) {
    new_class = "btn-" + new_class;
    button_object.removeClass("btn-warning");
    button_object.removeClass("btn-danger");
    button_object.removeClass("btn-success");
    button_object.removeClass("btn-info");
    button_object.removeClass("btn-primary");
    button_object.removeClass("btn-secondary");
    button_object.removeClass("btn-light");
    button_object.removeClass("btn-dark");
    button_object.addClass(new_class);
}