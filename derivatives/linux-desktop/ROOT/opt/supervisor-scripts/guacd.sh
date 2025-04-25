#!/bin/bash

sleep 2

socket="/tmp/.X11-unix/X${DISPLAY#*:}"
echo "Waiting for ${socket}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
while ! { [[ -S $socket ]] && timeout 1 socat -u OPEN:/dev/null "UNIX-CONNECT:${socket}" 2>/dev/null; }; do
  sleep 1 
done

guacd -b 127.0.0.1 -l 4822 -f 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
