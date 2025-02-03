#!/bin/bash

cron -f 2>&1 | tee -a /var/log/portal/cron.log
