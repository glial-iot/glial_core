var ucurrentpage = location.href;
var upos = ucurrentpage.search("system_");
var ulen = ucurrentpage.length;

ucurrentpage = ucurrentpage.slice(upos, ulen);
ucurrentpage = '/' + ucurrentpage

var dynamenu = new Vue({
    el: '#dynamenu',
    data: {
        menuitems: [],
        selected: ucurrentpage
    },
    created() {
        fetch('/system_menu_data')
            .then(response => response.json())
            .then(json => {
                this.menuitems = json;
            })
    }
})