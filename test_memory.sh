#!/bin/bash
set -e
swift build -c release
.build/release/AutoCleanMac &
PID=$!
sleep 3
ps -o rss= -p $PID
kill $PID
