#!/bin/bash

[[ ${AUTOSCALER,,} = 'true' ]] && echo "Refusing to start ${PROC_NAME} (AUTOSCALER=true)" | tee -a /var/log/portal/cron.log && exit

cron -f | tee -a /var/log/portal/cron.log