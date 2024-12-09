#!/bin/bash

[[ ${AUTOSCALER,,} = 'true' ]] && echo "Refusing to start ${PROC_NAME} (AUTOSCALER=true)" | tee -a "/var/log/portal/${PROC_NAME}.log" && exit
[[ $OPEN_BUTTON_PORT != "1111" ]] && echo "Refusing to start ${PROC_NAME} (OPEN_BUTTON_PORT!=1111)" | tee -a "/var/log/portal/${PROC_NAME}.log" && exit

cd /opt/portal-aio/portal
/opt/portal-aio/venv/bin/fastapi run --host 127.0.0.1 --port 11111 portal.py | tee -a "/var/log/portal/${PROC_NAME}.log"