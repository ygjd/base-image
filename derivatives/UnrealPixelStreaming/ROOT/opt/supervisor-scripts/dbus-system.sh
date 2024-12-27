#!/bin/bash

if [[ -f /run/dbus/pid ]]; then 
    kill -9 $(cat /run/dbus/pid)
    rm -f /run/dbus/pid
fi

dbus-daemon --system --nofork | tee -a "/var/log/portal/${PROC_NAME}.log"
