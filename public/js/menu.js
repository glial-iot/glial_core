var dynamenu = new Vue({
  el: '#dynamenu',
  data: 
{
    menuitems:
[
      { navname: 'Bus storage', navlink:'/bus_storage' },
      { navname: 'Logs', navlink:'/logger' },
      { navname: 'Edit', navlink:'/webedit_edit' },
      { navname: 'Control', navlink:'/control'  },
    { navname: 'Tarantool', navlink:'/tarantool'  }
    ]
  }

})