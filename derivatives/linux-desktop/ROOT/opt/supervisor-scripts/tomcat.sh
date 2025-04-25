#!/bin/bash

sleep 2

socket="/tmp/.X11-unix/X${DISPLAY#*:}"
echo "Waiting for ${socket}..." | tee -a "/var/log/portal/${PROC_NAME}.log"
while ! { [[ -S $socket ]] && timeout 1 socat -u OPEN:/dev/null "UNIX-CONNECT:${socket}" 2>/dev/null; }; do
  sleep 1 
done

# Create Guacamole config

cat > /etc/guacamole/noauth-config.xml << EOF
<configs>
    <config name="VNC Desktop" protocol="vnc">
        <param name="hostname" value="localhost" />
        <param name="port" value="5900" />
        <param name="password" value="${VNC_PASSWORD:-$OPEN_BUTTON_TOKEN}" />
    </config>
</configs>
EOF

/opt/tomcat9/bin/catalina.sh run 2>&1 | tee -a "/var/log/portal/${PROC_NAME}.log"
