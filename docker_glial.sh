#!/bin/sh

while true; do
   exec tarantool "/usr/local/bin/tarantool-entrypoint.lua" "glial_start.lua"
   sleep 2
done
