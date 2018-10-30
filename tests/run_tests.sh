#!/usr/bin/env bash
cd ..
today=`date +%Y-%m-%d-%H-%M-%S`
mkdir -p ./tests/logs
touch ./tests/logs/tarantool-$today.log
TARANTOOL_CONSOLE=0 HTTP_PORT=8888 TARANTOOL_WAL_DIR=test_db tarantool glue.lua &> ./tests/logs/tarantool-$today.log &
echo "Waiting Tarantool to initialize..."
sleep 1
cd ./tests/
busted tests.lua
rm -rf ../test_db
kill $!