#!/bin/bash

sleep 2

socket="/tmp/.X11-unix/X${DISPLAY#*:}"
echo "Waiting for ${socket}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
while ! { [[ -S $socket ]] && timeout 1 socat -u OPEN:/dev/null "UNIX-CONNECT:${socket}" 2>/dev/null; }; do
  sleep 1 
done

/usr/bin/x11vnc --storepasswd ${VNC_PASSWORD:-$OPEN_BUTTON_TOKEN} ${XDG_RUNTIME_DIR}/.vncpasswd 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"

/usr/bin/x11vnc -display ${DISPLAY} -forever -shared -rfbport 5900 -rfbauth ${XDG_RUNTIME_DIR}/.vncpasswd 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
