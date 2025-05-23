#!/bin/bash

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

# Check for vllm in the portal config
search_term="vllm"
search_pattern=$(echo "$search_term" | sed 's/[ _-]/[ _-]/g')
if ! grep -qiE "^[^#].*${search_pattern}" /etc/portal.yaml; then
    echo "Skipping startup for ${PROC_NAME} (not in /etc/portal.yaml)" | tee -a "/var/log/portal/${PROC_NAME}.log"
    exit 0
fi

# Activate the venv
. /venv/main/bin/activate

# Wait for provisioning to complete

while [ -f "/.provisioning" ]; do
    echo "$PROC_NAME startup paused until instance provisioning has completed (/.provisioning present)"
    sleep 10
done

# Launch vllm
cd ${WORKSPACE}

# User has not specified a remote Ray server
if [[ -z "$RAY_ADDRESS" || "$RAY_ADDRESS" = "127.0.0.1"* ]]; then
    export RAY_ADDRESS="127.0.0.1:6379"

    # Wait until ps aux shows ray is running
    max_attempts=30
    attempt=1
    
    while true; do
        if ps aux | grep -v grep | grep -q "gcs_server"; then
            echo "Ray process detected - continuing"
            break
        fi
        
        if [ $attempt -ge $max_attempts ]; then
            echo "Timeout waiting for Ray process to start"
            exit 1
        fi
        
        echo "Waiting for Ray process to start (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done
fi

# Automatically use all GPUs
if [[ ! $VLLM_ARGS =~ "tensor-parallel-size" && "${USE_ALL_GPUS,,}" = "true" ]]; then
    TENSOR_PARALLEL_SIZE="--tensor-parallel-size $GPU_COUNT"
else
    TENSOR_PARALLEL_SIZE=""
fi

vllm serve ${VLLM_MODEL:-} ${VLLM_ARGS:---host 127.0.0.1 --port 18000} ${TENSOR_PARALLEL_SIZE} 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
