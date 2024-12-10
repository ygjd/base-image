#!/bin/bash

# Remove Jupyter from the portal config if the external port 8080 isn't defined
if [ -z "${VAST_TCP_PORT_8080}" ]; then
    PORTAL_CONFIG=$(echo "$PORTAL_CONFIG" | tr '|' '\n' | grep -vi jupyter | tr '\n' '|' | sed 's/|$//')
fi

# Ensure correct port mappings for Jupyter 
if [[ -f /.launch ]] && grep -qi jupyter /.launch; then
    PORTAL_CONFIG="$(echo "$PORTAL_CONFIG" | sed 's#localhost:8080:18080#localhost:8080:8080#')"
else
    PORTAL_CONFIG="$(echo "$PORTAL_CONFIG" | sed 's#localhost:8080:8080#localhost:8080:18080#')"
fi

# First run...
if ! grep -q "CONTAINER_ID" /etc/environment; then
    # Populate /etc/environment - Skip HOME directory
    env | grep -v "^HOME=" > /etc/environment
    # Ensure users are dropped into the venv on login.  Must be after /.launch has updated PS1 
    echo 'cd ${DATA_DIR} && source ${DATA_DIR}/venv/main/bin/activate' | tee -a /root/.bashrc /home/user/.bashrc
    # Warn CLI users if the container provisioning is not yet complete. Red >>>
    echo '[[ -f /.provisioning ]] && echo -e "\e[91m>>>\e[0m Instance provisioning is not yet complete.\n\e[91m>>>\e[0m Required software may not be ready.\n\e[91m>>>\e[0m See /var/log/portal/provisioning.log or the Instance Portal web app for progress updates\n\n"' | tee -a /root/.bashrc /home/user/.bashrc
fi

# We may be busy for a while.
# Indicator for supervisor scripts to prevent launch during provisioning if necessary (if [[ -f /.provisioning ]] ...)
touch /.provisioning

# Let the 'user' account connect via SSH
/opt/instance-tools/bin/propagate_ssh_keys.sh

# Ensure files in $DATA_DIR (usually /workspace/) are on the top overlayfs layer
/opt/instance-tools/bin/hydrate_data_dir.sh &

# Generate the Jupyter certificate if run in SSH/Args Jupyter mode
if [ ! -f  /etc/openssl-san.cnf ] || ! grep -qi vast /etc/openssl-san.cnf; then
    echo "Generating certificates"
    echo '[req]' > /etc/openssl-san.cnf;
    echo 'default_bits       = 2048' >> /etc/openssl-san.cnf;
    echo 'distinguished_name = req_distinguished_name' >> /etc/openssl-san.cnf;
    echo 'req_extensions     = v3_req' >> /etc/openssl-san.cnf;

    echo '[req_distinguished_name]' >> /etc/openssl-san.cnf;
    echo 'countryName         = US' >> /etc/openssl-san.cnf;
    echo 'stateOrProvinceName = CA' >> /etc/openssl-san.cnf;
    echo 'organizationName    = Vast.ai Inc.' >> /etc/openssl-san.cnf;
    echo 'commonName          = vast.ai' >> /etc/openssl-san.cnf;

    echo '[v3_req]' >> /etc/openssl-san.cnf;
    echo 'basicConstraints = CA:FALSE' >> /etc/openssl-san.cnf;
    echo 'keyUsage         = nonRepudiation, digitalSignature, keyEncipherment' >> /etc/openssl-san.cnf;
    echo 'subjectAltName   = @alt_names' >> /etc/openssl-san.cnf;

    echo '[alt_names]' >> /etc/openssl-san.cnf;
    echo 'IP.1   = 0.0.0.0' >> /etc/openssl-san.cnf;

    openssl req -newkey rsa:2048 -subj "/C=US/ST=CA/CN=jupyter.vast.ai/" -nodes -sha256 -keyout /etc/instance.key -out /etc/instance.csr -config /etc/openssl-san.cnf
    curl --header 'Content-Type: application/octet-stream' --data-binary @//etc/instance.csr -X POST "https://console.vast.ai/api/v0/sign_cert/?instance_id=${CONTAINER_ID:-${VAST_CONTAINERLABEL#C.}}" > /etc/instance.crt;
fi

# Now we run supervisord - Put it in the background so provisioning can be monitored in Instance Portal
supervisord \
    -n \
    -u root \
    -c /etc/supervisor/supervisord.conf | \
        tee /var/log/portal/supervisor.log &
supervisord_pid=$!

# Provision the instance with a remote script - This will run on every startup so be careful to avoid re-downloading existing assets
# This is for configuration of existing images and will also allow for templates to be created without building docker images
# Experienced users will be able to convert the script to Dockerfile RUN and build a self-contained image
# NOTICE: If the provisioning script introduces new supervisor processes it must:
# - Remove the file /etc/portal.yaml
# - Re-declare env var PORTAL_CONFIG to include any new applications
# - run `supervisorctl reload`
# - Require the user to refresh the Instance Portal web app. TODO add auto page refresh in portal-aio package

if [[ -n $PROVISIONING_SCRIPT ]]; then
    echo "*****"
    echo "*"
    echo "*"
    echo "* Provisioning instance with remote script from ${PROVISIONING_SCRIPT}"
    echo "*"
    echo "* This may take a while.  Some services may not start until this process completes."
    echo "* To change this behavior you can edit or remove the PROVISIONING_SCRIPT environment variable."
    echo "*"
    echo "*"
    echo "*****"
    # Only download it if we don't already have it - Allows inplace modification & restart
    [[ ! -f /tmp/provisioning.sh ]] && curl -Lo /tmp/provisioning.sh $PROVISIONING_SCRIPT && \
    chmod +x /tmp/provisioning.sh && \
    /tmp/provisioning.sh 2>&1 | tee -a /var/log/portal/provisioning.log
    echo "Provisioning complete!" | tee -a /var/log/portal/provisioning.log
fi

# Remove the blocker and leave supervisord to run
rm -f /.provisioning
wait $supervisord_pid
