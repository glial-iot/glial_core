#!/bin/sh
set -e

#curl -s https://packagecloud.io/install/repositories/tarantool/1_10/script.deb.sh | sudo bash
#apt-get -y install tarantool=1.10.2.18.g480c55b67-1 tarantool-dev=1.10.2.18.g480c55b67-1 libmosquitto-dev



rm -rf ./temp_deb_packet_create

# Install rocks
cd ..
tarantoolctl rocks install http
tarantoolctl rocks install mqtt
tarantoolctl rocks install dump
tarantoolctl rocks install cron-parser
cd ./debian

# Copy files
mkdir ./temp_deb_packet_create
cd ./temp_deb_packet_create

mkdir -p ./glial/usr/share/tarantool/glial
cp ../../*.lua ./glial/usr/share/tarantool/glial
cp -r ../../libs ./glial/usr/share/tarantool/glial
cp -r ../../.rocks ./glial/usr/share/tarantool/glial
cp -r ../../panel ./glial/usr/share/tarantool/glial

mkdir -p ./glial/etc/tarantool/instances.enabled/
rm ./glial/usr/share/tarantool/glial/glial_start.lua
cp ../wb_instance_glial_start.lua ./glial/etc/tarantool/instances.enabled/glial.lua

# Change owner
chown -R root:root ./glial/
chown -R tarantool:tarantool ./glial/etc/tarantool/
chown -R tarantool:tarantool ./glial/usr/share/tarantool/

# Make deb metainfo
mkdir -p ./glial/DEBIAN

cp ../control ./glial/DEBIAN/control

VERSION=`git describe --dirty --always --tags | cut -c 2-`
VERSION_FOR_CONTROL="Version: "$VERSION
echo $VERSION_FOR_CONTROL >> ./glial/DEBIAN/control

SIZE=`du -sk  ./glial |awk '{print $1}'`
SIZE_FOR_CONTROL="Installed-Size: "$SIZE
echo $SIZE_FOR_CONTROL >> ./glial/DEBIAN/control

cp ../dirs ./glial/DEBIAN/dirs
cp ../prerm ./glial/DEBIAN/prerm
cp ../postinst ./glial/DEBIAN/postinst


# Add version file
echo $VERSION > ./glial/usr/share/tarantool/glial/VERSION

# Buld
dpkg-deb --build glial

mv glial.deb ../glial_$VERSION.deb

# Clear
cd ..
rm -rf ./temp_deb_packet_create
