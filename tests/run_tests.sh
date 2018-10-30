#!/usr/bin/env bash
cd ..
today=`date +%Y-%m-%d-%H-%M-%S`
mkdir -p ./tests/logs
touch ./tests/logs/tarantool-$today.log
TARANTOOL_CONSOLE=0 TEST_ENV=1 tarantool glue.lua &> ./tests/logs/tarantool-$today.log &
echo "Waiting Tarantool to initialize..."
sleep 1
busted ./tests/tests.lua
kill $!