#!/bin/bash

cron -f | tee -a /var/log/portal/cron.log
