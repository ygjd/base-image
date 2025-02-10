#!/bin/bash

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

# Check for $search_term in the portal config
search_term="open webui"
search_pattern=$(echo "$search_term" | sed 's/[ _-]/[ _-]?/gi')
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

# Launch Open Webui
cd ${$WORKSPACE}

[[ -z $WEBUI_SECRET_KEY ]] && export WEBUI_SECRET_KEY="${OPEN_BUTTON_TOKEN}"

[[ -z $OLLAMA_BASE_URL ]] && export OLLAMA_BASE_URL="http://127.0.0.1:21434"

[[ -z $OPENAI_API_BASE_URL ]] && export OPENAI_API_BASE_URL="http://127.0.0.1:20000"

[[ -z $OPENAI_API_KEY ]] && export OPENAI_API_KEY="${OPEN_BUTTON_TOKEN:-none}"

export DATA_DIR="${DATA_DIR:-${WORKSPACE:-/workspace}/webui}"
open-webui serve ${OPENWEBUI_ARGS:---host 127.0.0.1 --port 17500} | tee -a "/var/log/portal/${PROC_NAME}.log"
