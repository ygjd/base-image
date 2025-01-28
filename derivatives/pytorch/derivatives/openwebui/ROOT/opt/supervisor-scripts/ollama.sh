#!/bin/bash

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

# Check for $search_term in the portal config
search_term="ollama"
search_pattern=$(echo "$search_term" | sed 's/[ _-]/[ _-]?/gi')
if ! grep -qiE "^[^#].*${search_pattern}" /etc/portal.yaml; then
    echo "Skipping startup for ${PROC_NAME} (not in /etc/portal.yaml)" | tee -a "/var/log/portal/${PROC_NAME}.log"
    exit 0
fi

# Wait for provisioning to complete

while [ -f "/.provisioning" ]; do
    echo "$PROC_NAME startup paused until instance provisioning has completed (/.provisioning present)"
    sleep 10
done

# Ensure models and config are saved in the workspace
if [[ ! -L /root/.ollama ]]; then
    ln -s ${WORKSPACE}/ollama /root/.ollama
fi

ollama serve ${OLLAMA_ARGS} | tee -a "/var/log/portal/${PROC_NAME}.log"
