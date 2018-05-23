let dynamenu = new Vue({
    el: '#dynamenu',
    data: {
        menuitems: [],
        current_href: location.pathname
    },
    created() {
        fetch('/system_menu_data')
            .then(response => response.json())
            .then(json => {
                this.menuitems = json;
            })
    }
})