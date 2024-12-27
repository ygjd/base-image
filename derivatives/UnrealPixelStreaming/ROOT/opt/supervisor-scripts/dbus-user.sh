#!/bin/bash

while [[ ! -S /run/dbus/system_bus_socket ]]; do
    echo "Waiting for system dbus socket..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

dbus-daemon --config-file=/home/user/.config/dbus/session-local.conf --nofork | tee -a "/var/log/portal/${PROC_NAME}.log"

