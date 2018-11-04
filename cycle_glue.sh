#!/bin/sh

while true; do
   TARANTOOL_CONSOLE=1 tarantool glue_start.lua
   echo "\n\nStopped, wait 2s...\n"
   echo "Press Ctrl-C for exit\n"
   sleep 2
done
