#!/bin/bash

# We're going to touch all the files in ${DATA_DIRECTORY} 
# This will use some space on the upper layer but it will make the directory completely portable between instances

if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Directory $DATA_DIRECTORY not found" | tee -a /var/log/portal/data-hydrate.log
    exit 1
fi

if [[ -f "${DATA_DIRECTORY}/.hydrated" ]]; then
    echo "Found ${DATA_DIRECTORY}/.hydrated - Skipping touch" | tee -a /var/log/portal/data-hydrate.log
    exit 0
fi

if [[ ${DATA_DIRECTORY_HYDRATE,,} = "false" ]]; then
    echo "Skipping ${DATA_DIRECTORY} hydration (DATA_DIRECTORY_HYDRATE=false)" | tee -a /var/log/portal/data-hydrate.log
    exit 0
fi

echo "Hydratring ${DATA_DIRECTORY}. This will take a moment" | tee -a /var/log/portal/data-hydrate.log

# Touch all files - Do not follow symlinks but modify their timestamp.  Optimize for threadcount. 
find "$DATA_DIRECTORY" -print0 | xargs -0 -P $(nproc) -n 100 touch -h
touch ${DATA_DIRECTORY}/.hydrated
echo "Hydrated ${DATA_DIRECTORY}!" | tee -a /var/log/portal/data-hydrate.log
