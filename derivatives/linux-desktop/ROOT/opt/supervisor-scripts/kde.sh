#!/bin/bash

socket="$XDG_RUNTIME_DIR/pipewire-0"
echo "Waiting for ${socket}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
while ! { [[ -S $socket ]] && timeout 1 socat -u OPEN:/dev/null "UNIX-CONNECT:${socket}" 2>/dev/null; }; do
    sleep 1
done

export XDG_SESSION_ID="${DISPLAY#*:}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"
export SHELL=${SHELL:-/bin/bash}

if [ -n "$(nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1)" ] || [ -n "$(ls -A /dev/dri 2>/dev/null)" ]; then
  export VGL_FPS="${DISPLAY_REFRESH}"
  /usr/bin/vglrun -d "${VGL_DISPLAY:-egl}" +wm /usr/bin/dbus-launch --exit-with-session /usr/bin/startplasma-x11 | tee -a "/var/log/portal/${PROC_NAME}.log" \
    2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
else
  /usr/bin/dbus-launch --exit-with-session /usr/bin/startplasma-x11 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
fi
