#!/bin/sh
rm -rf ./temp_deb_packet_create

mkdir ./temp_deb_packet_create
cd ./temp_deb_packet_create
mkdir -p ./glue/debian

cp ../control ./glue/debian/control
cp ../dirs ./glue/debian/dirs

mkdir -p ./glue/usr/share/tarantool/glue
cp ../../*.lua ./glue/usr/share/tarantool/glue
cp -r ../../libs ./glue/usr/share/tarantool/glue

mkdir -p ./glue/etc/tarantool/instances.enabled/
mv ./glue/usr/share/tarantool/glue/glue_start.lua ./glue/etc/tarantool/instances.enabled/glue.lua


chown -R root:root ./glue/
chown -R tarantool:tarantool ./glue/etc/tarantool/
chown -R tarantool:tarantool ./glue/usr/share/tarantool/

dpkg-deb --build glue

mv glue.deb glue_0.73-82-gfd80b2b_all.deb

lintian glue_0.73-82-gfd80b2b_all.deb
