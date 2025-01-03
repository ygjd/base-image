#!/bin/bash

# This service starts whether it has been included in PORTAL_CONFIG or not.
# If it is not, there will be no listening in the external interface - This is ok, user probably wants SSH forwarding or autoscaler

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
        ${COMFYUI_ARGS} --disable-auto-launch --port 18188
