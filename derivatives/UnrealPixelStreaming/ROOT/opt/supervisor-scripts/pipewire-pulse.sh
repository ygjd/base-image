#!/bin/bash

while ! pgrep -f "wireplumber" > /dev/null; do
    echo "Waiting for wireplumber..."
    sleep 1
done

pipewire-pulse | tee -a "/var/log/portal/${PROC_NAME}.log"