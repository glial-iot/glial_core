

var dynamenu = new Vue({
  el: '#dynamenu',
  data: 
{    menuitems:  []    
},
	
        created(){
fetch('http://192.168.1.45:8080/system_menu_data')
.then(response => response.json())
.then(json=> {

this.menuitems= json;
	console.log(this.menuitems);
})

		
}
})
	