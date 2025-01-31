#!/bin/bash

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..."
    sleep 1
done

# Check for $search_term in the portal config
search_term="instance portal"
search_pattern=$(echo "$search_term" | sed 's/[ _-]/[ _-]?/gi')
if ! grep -qiE "^[^#].*${search_pattern}" /etc/portal.yaml; then
    echo "Skipping startup for ${PROC_NAME} (not in /etc/portal.yaml)"
    exit 0
fi

cd /opt/portal-aio/portal
/opt/portal-aio/venv/bin/fastapi run --host 127.0.0.1 --port 11111 portal.py
