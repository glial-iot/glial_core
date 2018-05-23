let ucurrentpage = location.href;
let upos = ucurrentpage.search("system_");
let ulen = ucurrentpage.length;

ucurrentpage = ucurrentpage.slice(upos, ulen);
ucurrentpage = '/' + ucurrentpage

let dynamenu = new Vue({
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