#!/bin/bash

sleep 2

socket="$XDG_RUNTIME_DIR/pipewire-0"
echo "Waiting for ${socket}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
while ! { [[ -S $socket ]] && timeout 1 socat -u OPEN:/dev/null "UNIX-CONNECT:${socket}" 2>/dev/null; }; do
    sleep 1
done

rm -rf "${HOME}/.cache/gstreamer-1.0"

export TURN_HOST=${TURN_HOST:-$PUBLIC_IPADDR}
export TURN_PORT=${TURN_PORT:-$VAST_TCP_PORT_73478}
export TURN_USERNAME=${TURN_USERNAME:-turnuser}
export TURN_PASSWORD=${TURN_PASSWORD:-${OPEN_BUTTON_TOKEN:-password}}

if [[ -n $VAST_UDP_PORT_73478 ]]; then
    export TURN_PROTOCOL=${TURN_PROTOCOL:-udp}
else
    export TURN_PROTOCOL=${TURN_PROTOCOL:-tcp}
fi

. /opt/gstreamer/gst-env

selkies-gstreamer --addr=127.0.0.1 --port=16100 \
  --enable_https=false \
  --encoder=${SELKIES_ENCODER:-x264enc} \
  --enable_basic_auth=false \
  --enable_resize=false \
  --turn_host=${TURN_HOST} \
  --turn_port=${TURN_PORT} \
  --turn_protocol=${TURN_PROTOCOL} \
  --turn_username=${TURN_USERNAME} \
  --turn_password=${TURN_PASSWORD} 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"