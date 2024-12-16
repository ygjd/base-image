#!/bin/bash

[[ ${AUTOSCALER,,} = 'true' ]] && echo "Refusing to start ${PROC_NAME} (AUTOSCALER=true)" && exit
[[ $OPEN_BUTTON_PORT != "1111" ]] && echo "Refusing to start ${PROC_NAME} (OPEN_BUTTON_PORT!=1111)" | tee -a "/var/log/portal/${PROC_NAME}.log" && exit

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

# rudimentary check for tensorboard in the portal config
search_pattern=$(echo "$PROC_NAME" | sed 's/[ _-]/[ _-]/g')
if ! grep -qiE "^[^#].*${search_pattern}" /etc/portal.yaml; then
    echo "Skipping startup for ${PROC_NAME} (not in /etc/portal.yaml)" | tee -a "/var/log/portal/${PROC_NAME}.log"
    exit 0
fi

tensorboard --port 16006 --logdir ${TENSORBOARD_LOG_DIR:-${DATA_DIRECTORY:-/workspace/}} | tee -a "/var/log/portal/${PROC_NAME}.log"