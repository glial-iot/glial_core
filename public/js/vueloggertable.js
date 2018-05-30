// register the grid component

Vue.component('vue-grid', {
	template: '#grid-template',
	props: {
		data: Array,
		updateinterval: Number,
		deletesuccess: Boolean,
		filteredData: Array,
		filterkey: String
	}
})
// bootstrap the demo
var vtable = new Vue({
	el: '#vtable',
	data: {
		gridData: undefined,
		interval: undefined,
		deletesuccess: undefined,
		filterkey: 'ALL'
	},

	created: function () {
		this.loadData();
		var newinterval = 3000;
		this.Updateintervalvalue(newinterval);

	},
	methods: {
		loadData: function () {
			{
				fetch('/system_logger_data?item=ALL')
					.then(response => response.json())
					.then(json => {
						this.gridData = json;
						if (this.filterkey != 'ALL') {
							this.Filter()
						};

					})
			}
		},
		Updateintervalvalue: function (newinterval) {
			clearInterval(this.Periodicupdate);
			this.interval = newinterval;
			this.Periodicupdate = setInterval(function () {
				this.loadData();
			}.bind(this), newinterval);
		},
		Updatefilterkey: function (newfilter) {
			this.filterkey = newfilter;
			this.loadData();
		},
		Filter: function () {
			var data = this.gridData;
			var currentfilter = this.filterkey;
			data = data.filter(function (item, index, data) {
				return item.level == currentfilter;
			})
			this.gridData = data;
		},

		Clearlogs: function () {
			fetch('/system_logger_action?action=delete_logs')
				.then(response => response.json())
				.then(json => {
					this.deletesuccess = json.result;
					setTimeout(() => {
						this.deletesuccess = false;
					}, 2000)
				})


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
			el.parentElement.childNodes[2].classList.add('highlight')
			el.parentElement.childNodes[4].classList.add('highlight')
			el.parentElement.childNodes[0].classList.add('highlight')

			setTimeout(() => {
				el.parentElement.childNodes[2].classList.remove('highlight')
				el.parentElement.childNodes[4].classList.remove('highlight')
				el.parentElement.childNodes[0].classList.remove('highlight')
				el.classList.remove('highlight')
			}, 2000)
		}
	},
	unbind(el) {
		hlCache.remove(el)
	}
})
