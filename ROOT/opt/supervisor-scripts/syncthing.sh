#!/bin/bash

# Syncthing daemonises and the new process is out-of-group.  Ensure it is fully killed on exit
trap 'pgrep syncthing | grep -v "^$$\$" | xargs -r kill -9' EXIT

[[ ${AUTOSCALER,,} = 'true' ]] && echo "Refusing to start ${PROC_NAME} (AUTOSCALER=true)" && exit
[[ $OPEN_BUTTON_PORT != "1111" ]] && echo "Refusing to start ${PROC_NAME} (OPEN_BUTTON_PORT!=1111)" | tee -a "/var/log/portal/${PROC_NAME}.log" && exit

# User can configure startup by removing the reference in /etc.portal.yaml - So wait for that file and check it
while [ ! -f "$(realpath -q /etc/portal.yaml 2>/dev/null)" ]; do
    echo "Waiting for /etc/portal.yaml before starting ${PROC_NAME}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
    sleep 1
done

# rudimentary check for syncthing in the portal config
search_pattern=$(echo "$PROC_NAME" | sed 's/[ _-]/[ _-]/g')
if ! grep -qiE "^[^#].*${search_pattern}" /etc/portal.yaml; then
    echo "Skipping startup for ${PROC_NAME} (not in /etc/portal.yaml)" | tee -a "/var/log/portal/${PROC_NAME}.log"
    exit 0
fi

# We run this as root user because the default SSH login for Vast.ai instances is for root and we want to avoid permission issues
run_syncthing() {
    API_KEY=${OPEN_BUTTON_TOKEN:-$(openssl rand -hex 16)}
    /opt/syncthing/syncthing generate
    sed -i '/^\s*<listenAddress>/d' "/root/.local/state/syncthing/config.xml"
    /opt/syncthing/syncthing --gui-address="127.0.0.1:18384" --gui-apikey="${API_KEY}" --no-upgrade &
    syncthing_pid=$!
    echo "Waiting on $syncthing_pid"

    until curl --output /dev/null --silent --head --fail "http://127.0.0.1:18384"; do
        echo "Waiting for syncthing server...\n"
        sleep 1
    done

    # Execute configuration commands with retries
    run_with_retry /opt/syncthing/syncthing cli --gui-address="127.0.0.1:18384" --gui-apikey="${API_KEY}" config gui insecure-admin-access set true 
    run_with_retry /opt/syncthing/syncthing cli --gui-address="127.0.0.1:18384" --gui-apikey="${API_KEY}" config gui insecure-skip-host-check set true
    run_with_retry /opt/syncthing/syncthing cli --gui-address="127.0.0.1:18384" --gui-apikey="${API_KEY}" config options raw-listen-addresses add "tcp://0.0.0.0:${VAST_TCP_PORT_72299}"
    wait $syncthing_pid
}

run_with_retry() {
    until "$@"; do
        printf "Command failed. Retrying...\n"
        sleep 1
    done
}

run_syncthing | tee -a "/var/log/portal/${PROC_NAME}.log"