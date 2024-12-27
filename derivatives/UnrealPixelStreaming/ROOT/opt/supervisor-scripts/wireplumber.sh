#!/bin/bash

while [[ ! -S /run/user/1001/pipewire-0 ]]; do
    echo "Waiting for pipewire socket..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

wireplumber | tee -a "/var/log/portal/${PROC_NAME}.log"

