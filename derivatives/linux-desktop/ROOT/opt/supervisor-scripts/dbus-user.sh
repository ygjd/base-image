#!/bin/bash

socket=/run/dbus/system_bus_socket
echo "Waiting for ${socket}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
while ! { [[ -S $socket ]] && timeout 1 socat -u OPEN:/dev/null "UNIX-CONNECT:${socket}" 2>/dev/null; }; do
    sleep 1
done

dbus-daemon --config-file=/home/user/.config/dbus/session-local.conf --nofork 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"

