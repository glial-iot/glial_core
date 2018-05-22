var dynamenu = new Vue({
    el: '#dynamenu',
    data: {
        menuitems: []
    },
    created() {
        fetch('/system_menu_data')
            .then(response => response.json())
            .then(json => {
                this.menuitems = json;
               })
    }
})
