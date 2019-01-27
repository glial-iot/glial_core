#!/usr/bin/env bash

cd ..
HTTP_PORT=8888 TARANTOOL_WAL_DIR=test_db tarantool glial_start.lua >> ./tests/logs/tarantool-$TIME.log 2>&1
