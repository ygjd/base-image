# Choose a base image.  Sensible options include ubuntu:xx.xx, nvidia/cuda:xx-cuddnx
ARG BASE_IMAGE=nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

### Build Caddy with single port TLS redirect
FROM golang:1.22 AS caddy_builder

# Install required packages
RUN apt-get update && apt-get install -y \
    wget \
    git

# Install xcaddy for the current architecture
RUN wget -O xcaddy.deb "https://github.com/caddyserver/xcaddy/releases/download/v0.4.2/xcaddy_0.4.2_linux_$(dpkg --print-architecture).deb" && \
    apt-get install -y ./xcaddy.deb

# Build Caddy
ARG TARGETARCH
RUN GOARCH=$TARGETARCH xcaddy build \
    --with github.com/caddyserver/caddy/v2=github.com/ai-dock/caddy/v2@httpredirect \
    --with github.com/caddyserver/replace-response

### Main Build ###

FROM ${BASE_IMAGE} AS main_build

# Maintainer details
LABEL org.opencontainers.image.source="https://github.com/vastai/"
LABEL org.opencontainers.image.description="Base image suitable for Vast.ai."
LABEL maintainer="Vast.ai Inc <contact@vast.ai>"

# Support pipefail so we don't build broken images
SHELL ["/bin/bash", "-c"]

# Vast.ai environment variables used for Jupyter & Data sync
ENV JUPYTER_DIR=/
ENV DATA_DIR=/workspace/
# Ubuntu 24.04 requires this for compatibility with out /.launch script
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Don't ask questions we cannot answer during the build
ENV DEBIAN_FRONTEND=noninteractive
# Allow immediate output
ENV PYTHONUNBUFFERED=1

# Interactive container
RUN yes | unminimize

# Create a useful base environment with commonly used tools
ARG TARGETARCH
RUN \
    set -eo pipefail && \
    ([ $TARGETARCH = "arm64" ] && echo "Skipping i386 architecture for ARM builds" || dpkg --add-architecture i386) && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
        # Base system utilities
        ca-certificates \
        gpg-agent \
        software-properties-common \
        openssh-server \
        curl \
        wget \
        sudo \
        moreutils \
        nano \
        less \
        jq \
        git \
        man \
        # System monitoring & debugging
        htop \
        iotop \
        strace \
        lsof \
        procps \
        psmisc \
        iproute2 \
        nvtop \
        # Development essentials
        build-essential \
        cmake \
        ninja-build \
        gdb \
        python3-full \
        python3-dev \
        python3-pip \
        # Network utilities
        netcat \
        iputils-ping \
        traceroute \
        # File management
        rsync \
        rclone \
        zip \
        unzip \
        # Performance analysis
        perf-tools-unstable \
        linux-tools-common \
        # Process management
        supervisor \
        cron \
        # Required for cron logging
        rsyslog


# Add a normal user account - Some applications don't like to run as root so we should save our users some time.  Give it unfettered access to sudo
RUN \
    set -eo pipefail && \
    groupadd -g 1001 user && \
    useradd -ms /bin/bash user -u 1001 -g 1001 && \
    echo "PATH=${PATH}" >> /home/user/.bashrc && \
    echo "user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/user && \
    sudo chmod 0440 /etc/sudoers.d/user && \
    mkdir -m 700 -p /run/user/1001 && \
    chown 1001:1001 /run/user/1001 && \
    mkdir /run/dbus && \
    mkdir ${DATA_DIR} && \
    chown 1001:1001 ${DATA_DIR}

# Add the 'service portal' web app into this container to avoid needing to specify in onstart.  
# We will launch each component with supervisor - Not the standalone launch script.
COPY ./portal-aio /opt/portal-aio
COPY --from=caddy_builder /go/caddy /opt/portal-aio/caddy_manager/caddy
ARG TARGETARCH
RUN \
    set -eo pipefail && \
    python3 -m venv /opt/portal-aio/venv && \
    mkdir -m 770 -p /var/log/portal && \
    mkdir -p opt/instance-tools/bin/ && \
    /opt/portal-aio/venv/bin/pip install -r /opt/portal-aio/requirements.txt 2>&1 | tee -a /var/log/portal/portal.log && \
    wget -O /opt/portal-aio/tunnel_manager/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${TARGETARCH} && \
    chmod +x /opt/portal-aio/tunnel_manager/cloudflared && \
    # Make these portal-provided tools easily reachable
    ln -s /opt/portal-aio/caddy_manager/caddy /opt/instance-tools/bin/caddy && \
    ln -s /opt/portal-aio/tunnel_manager/cloudflared /opt/instance-tools/bin/cloudflared


# Initial config will write /etc/portal.yaml
# Start with only Instance Portal, Jupyter & Syncthing
# Any services we define in /opt/supervisor-scripts/bin and /etc/supervisor/conf.d can use the config at /etc/portal.yaml to defer/disable startup
ENV PORTAL_CONFIG="localhost:1111:11111:/:Instance Portal|localhost:8080:18080:/:Jupyter|localhost:8384:18384:/:Syncthing"

# Populate the system Python environment with useful tools.  Add jupyter to speed up instance creation and allow configuration in advance
RUN \
    set -eo pipefail && \
    pip install --no-cache-dir \
        jupyter \
        vastai

# Install Syncthing
ARG TARGETARCH
RUN \
    set -eo pipefail && \
    SYNCTHING_VERSION="$(curl -fsSL "https://api.github.com/repos/syncthing/syncthing/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')" && \
    SYNCTHING_URL="https://github.com/syncthing/syncthing/releases/download/v${SYNCTHING_VERSION}/syncthing-linux-${TARGETARCH}-v${SYNCTHING_VERSION}.tar.gz" && \
    mkdir /opt/syncthing/ && \
    wget -O /opt/syncthing.tar.gz $SYNCTHING_URL && (cd /opt && tar -zxf syncthing.tar.gz -C /opt/syncthing/ --strip-components=1) && rm -f /opt/syncthing.tar.gz

RUN \
    set -eo pipefail && \
    mkdir -p ${DATA_DIR}/venv && \
    # Create a virtual env where we will install our packages.  It's portable unlike the system site-packages
    python3 -m venv ${DATA_DIR}/venv/main && \
    ${DATA_DIR}/venv/main/bin/pip install --no-cache-dir \
        wheel \
        huggingface_hub[cli] \
        ipykernel \
        ipywidgets && \
    ${DATA_DIR}/venv/main/bin/python -m ipykernel install \
        --name="main" \
        --display-name="Python3 (main venv)" && \
    # Re-add as default.  We don't want users accidentally installing packages in the system python
    ${DATA_DIR}/venv/main/bin/python -m ipykernel install \
        --name="python3" \
        --display-name="Python3 (ipykernel)"

# Add some useful scripts and config files
COPY ./ROOT/ /
ENV PATH=/opt/instance-tools/bin:${PATH}

CMD ["entrypoint.sh"]

WORKDIR ${DATA_DIR}
