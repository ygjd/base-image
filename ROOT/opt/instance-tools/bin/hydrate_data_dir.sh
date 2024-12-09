#!/bin/bash

# We're going to touch all the files in ${DATA_DIR} 
# This will use some space on the upper layer but it will make the directory completely portable between instances

if [[ ! -d "$DATA_DIR" ]]; then
    echo "Error: Directory $DATA_DIR not found" | tee -a /var/log/portal/data-hydrate.log
    exit 1
fi

if [[ -f "${DATA_DIR}/.hydrated" ]]; then
    echo "Found ${DATA_DIR}/.hydrated - Skipping touch" | tee -a /var/log/portal/data-hydrate.log
    exit 0
fi

if [[ ${DATA_DIR_HYDRATE,,} = "false" ]]; then
    echo "Skipping ${DATA_DIR} hydration (DATA_DIR_HYDRATE=false)" | tee -a /var/log/portal/data-hydrate.log
    exit 0
fi

echo "Hydratring ${DATA_DIR}. This will take a moment" | tee -a /var/log/portal/data-hydrate.log

# Touch all files - Do not follow symlinks but modify their timestamp.  Optimize for threadcount. 
find "$DATA_DIR" -print0 | xargs -0 -P $(nproc) -n 100 touch -h
touch ${DATA_DIR}/.hydrated
echo "Hydrated ${DATA_DIR}!" | tee -a /var/log/portal/data-hydrate.log
