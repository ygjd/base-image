#!/bin/bash

# Run the caddy configurator
cd /opt/portal-aio/caddy_manager
/opt/portal-aio/venv/bin/python caddy_config_manager.py | tee -a "/var/log/portal/${PROC_NAME}.log"

# Ensure the portal config file exists if running without PORTAL_CONFIG
touch /etc/portal.yaml

if [[ -f /etc/Caddyfile ]]; then
    # Frontend log viewer will force a page reload if this string is detected
    echo "Starting Caddy..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    /opt/portal-aio/caddy_manager/caddy run --config /etc/Caddyfile 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
else
    echo "Not Starting Caddy - No config file was generated" | tee -a "/var/log/portal/${PROC_NAME}.log"
fi
