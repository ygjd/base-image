#!/bin/bash

while ! pgrep -f "\-\-config-file=/home/user/.config/dbus/session-local.conf" > /dev/null; do
    echo "Waiting for dbus process with local config..."
    sleep 1
done

pipewire | tee -a "/var/log/portal/${PROC_NAME}.log"