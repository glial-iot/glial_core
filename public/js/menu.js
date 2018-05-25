Vue.component('dynamenu-component', {
	props: {
		item: Object,
		current_href: String
	},
	template: '<a v-bind:href="item.href" class="nav-link" v-bind:class="{ active: current_href === item.href }" @click="current_href = item.href"><i v-bind:class="item.icon"></i> {{item.name}}</a>'
})


new Vue({
	el: '#dynamenu-instance',
	data: {
		menuitems: undefined,
		current_href: location.pathname
	},
	created() {

		fetch('http://192.168.1.45:8080/system_menu_data')
			.then(response => response.json())
			.then(json => {
				this.menuitems = json;
			})
	}
})
