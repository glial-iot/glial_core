#!/bin/sh

while true; do
   TARANTOOL_CONSOLE=1 tarantool glue.lua
   sleep 2
done
