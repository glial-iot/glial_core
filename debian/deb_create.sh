#!/bin/sh
set -e

#luarocks install cqueues CRYPTO_LIBDIR=/usr/lib/aarch64-linux-gnu/ OPENSSL_LIBDIR=/usr/lib/aarch64-linux-gnu/
#luarocks install luaossl CRYPTO_LIBDIR=/usr/lib/aarch64-linux-gnu/ OPENSSL_LIBDIR=/usr/lib/aarch64-linux-gnu/
#apt-get install m4


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

mkdir -p ./glue/usr/share/tarantool/glue
cp ../../*.lua ./glue/usr/share/tarantool/glue
cp -r ../../libs ./glue/usr/share/tarantool/glue
cp -r ../../.rocks ./glue/usr/share/tarantool/glue
cp -r ../../panel ./glue/usr/share/tarantool/glue

mkdir -p ./glue/etc/tarantool/instances.enabled/
rm ./glue/usr/share/tarantool/glue/glue_start.lua
cp ../wb_instance_glue_start.lua ./glue/etc/tarantool/instances.enabled/glue.lua

# Change owner
chown -R root:root ./glue/
chown -R tarantool:tarantool ./glue/etc/tarantool/
chown -R tarantool:tarantool ./glue/usr/share/tarantool/

# Make deb metainfo
mkdir -p ./glue/DEBIAN

cp ../control ./glue/DEBIAN/control

VERSION=`git describe --dirty --always --tags | cut -c 2-`
VERSION_FOR_CONTROL="Version: "$VERSION
echo $VERSION_FOR_CONTROL >> ./glue/DEBIAN/control

SIZE=`du -sk  ./glue |awk '{print $1}'`
SIZE_FOR_CONTROL="Installed-Size: "$SIZE
echo $SIZE_FOR_CONTROL >> ./glue/DEBIAN/control

cp ../dirs ./glue/DEBIAN/dirs
cp ../prerm ./glue/DEBIAN/prerm
cp ../postinst ./glue/DEBIAN/postinst


# Add version file
echo $VERSION > ./glue/usr/share/tarantool/glue/VERSION

# Buld
dpkg-deb --build glue

mv glue.deb ../glue_$VERSION.deb

# Clear
cd ..
rm -rf ./temp_deb_packet_create
