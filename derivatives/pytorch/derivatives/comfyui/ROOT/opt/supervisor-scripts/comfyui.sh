#!/bin/bash

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

# rudimentary check for comfyui in the portal config
search_pattern=$(echo "$PROC_NAME" | sed 's/[ _-]/[ _-]/g')
if ! grep -qiE "^[^#].*${search_pattern}" /etc/portal.yaml; then
    echo "Skipping startup for ${PROC_NAME} (not in /etc/portal.yaml)" | tee -a "/var/log/portal/${PROC_NAME}.log"
    exit 0
fi

# Activate the venv
. ${DATA_DIRECTORY}venv/main/bin/activate

# Wait for provisioning to complete

while [ -f "/.provisioning" ]; do
    echo "$PROC_NAME startup paused until instance provisioning has completed (/.provisioning present)"
    sleep 10
done

# Launch ComfyUI
cd ${DATA_DIRECTORY}ComfyUI
LD_PRELOAD=libtcmalloc_minimal.so.4 \
        python main.py \
        ${COMFYUI_ARGS:- --disable-auto-launch --port 18188} | tee -a "/var/log/portal/${PROC_NAME}.log"
