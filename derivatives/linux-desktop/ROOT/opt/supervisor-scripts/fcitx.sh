#!/bin/bash

sleep 2

socket="$XDG_RUNTIME_DIR/pipewire-0"
echo "Waiting for ${socket}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
while ! { [[ -S $socket ]] && timeout 1 socat -u OPEN:/dev/null "UNIX-CONNECT:${socket}" 2>/dev/null; }; do
  sleep 1 
done

fcitx 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"

