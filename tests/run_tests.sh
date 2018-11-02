#!/usr/bin/env bash

today=`date +%Y-%m-%d-%H-%M`
touch ./logs/tarantool-$today.log
mkdir -p ./logs

busted tests.lua
# Run only tests with #tarantool tag
# busted -t "backups" tests.lua

rm -rf ../test_db