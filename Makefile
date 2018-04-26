deploy_ud:
	scp -i ~/.ssh/id_rsa_macmini_server *.lua  vvzvlad@192.168.1.64:/Users/vvzvlad/tarantool-server/
	scp -i ~/.ssh/id_rsa_macmini_server ./templates/*  vvzvlad@192.168.1.64:/Users/vvzvlad/tarantool-server/templates/
	osascript -e 'display notification with title "Script updated" subtitle "192.168.1.67 (Nokia office)"'

deploy_auto:
	watchmedo shell-command --drop --command='make'
