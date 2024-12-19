#!/bin/bash

[[ ${AUTOSCALER,,} = 'true' ]] && echo "Refusing to start ${PROC_NAME} (AUTOSCALER=true)" | tee -a "/var/log/portal/${PROC_NAME}.log" && exit
[[ $OPEN_BUTTON_PORT != "1111" ]] && echo "Refusing to start ${PROC_NAME} (OPEN_BUTTON_PORT!=1111)" | tee -a "/var/log/portal/${PROC_NAME}.log" && exit

# Run the caddy configurator
cd /opt/portal-aio/caddy_manager
/opt/portal-aio/venv/bin/python caddy_config_manager.py | tee -a "/var/log/portal/${PROC_NAME}.log"

# Frontend log viewer will force a page reload if this string is detected
echo "Starting Caddy..." | tee -a "/var/log/portal/${PROC_NAME}.log"

/opt/portal-aio/caddy_manager/caddy run --config /etc/Caddyfile | tee -a "/var/log/portal/${PROC_NAME}.log"