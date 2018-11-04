#!/bin/sh
rm -rf ./temp_deb_packet_create

cd ..
tarantoolctl rocks install http
tarantoolctl rocks install mqtt
tarantoolctl rocks install dump
tarantoolctl rocks install cron-parser
cd ./debian

mkdir ./temp_deb_packet_create
cd ./temp_deb_packet_create
mkdir -p ./glue/DEBIAN

cp ../control ./glue/DEBIAN/control
cp ../dirs ./glue/DEBIAN/dirs

mkdir -p ./glue/usr/share/tarantool/glue
cp ../../*.lua ./glue/usr/share/tarantool/glue
cp -r ../../libs ./glue/usr/share/tarantool/glue
cp -r ../../.rocks ./glue/usr/share/tarantool/glue
cp -r ../../panel ./glue/usr/share/tarantool/glue

mkdir -p ./glue/etc/tarantool/instances.enabled/
rm ./glue/usr/share/tarantool/glue/glue_start.lua
cp ../wirenboard/glue_start.lua ./glue/etc/tarantool/instances.enabled/glue.lua


chown -R root:root ./glue/
chown -R tarantool:tarantool ./glue/etc/tarantool/
chown -R tarantool:tarantool ./glue/usr/share/tarantool/

dpkg-deb --build glue

GIT=`git describe --dirty --always --tags`
mv glue.deb ../glue_$GIT.deb

cd ..
rm -rf ./temp_deb_packet_create

#lintian glue_0.73-82-gfd80b2b_all.deb
