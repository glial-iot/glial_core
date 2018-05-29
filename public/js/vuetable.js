// register the grid component

Vue.component('vue-grid', {
	template: '#grid-template',
	props: {
		data: Array,
		updateinterval: Number
	}
})

// bootstrap the demo
var vuetable = new Vue({
	el: '#vtable',
	data: {
		gridData: undefined,
		interval: undefined
	},

	created: function () {
		this.loadData();
		var newinterval = 3000;
		this.Updateintervalvalue(newinterval);

	},
	methods: {
		loadData: function () {
			{
				fetch('/system_bus_data?item=ALL')
					.then(response => response.json())
					.then(json => {
						console.log(json);
						this.gridData = json;

					})

			}
		},
		Updateintervalvalue: function (newinterval) {
			clearInterval(this.Periodicupdate);
			console.log('NewInterval');
			this.interval = newinterval;
			this.Periodicupdate = setInterval(function () {
				this.loadData();
			}.bind(this), newinterval);


		}
	}
});

//console.clear()

const hlCache = new Map()

Vue.directive('highlight', {

	bind(el, {
		value
	}) {
		hlCache.set(el, value)
	},
	componentUpdated(el, {
		value
	}) {
		if (hlCache.get(el) !== value) {
			hlCache.set(el, value)

			el.classList.add('highlight')
			el.parentElement.childNodes[0].classList.add('highlight')
			el.parentElement.childNodes[1].classList.add('highlight')
			el.parentElement.childNodes[2].classList.add('highlight')

			setTimeout(() => {
				el.parentElement.childNodes[2].classList.remove('highlight')
				el.parentElement.childNodes[1].classList.remove('highlight')
				el.parentElement.childNodes[0].classList.remove('highlight')
				el.classList.remove('highlight')
			}, 2000)
		}
	},
	unbind(el) {
		hlCache.remove(el)
	}
})
