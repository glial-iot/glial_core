#!/usr/bin/env bash

mkdir -p ./logs

busted tests.lua
# Run only tests with #backups tag
# busted -t "backups" tests.lua

rm -rf ../test_db