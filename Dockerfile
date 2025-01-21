# Choose a base image.  Sensible options include ubuntu:xx.xx, nvidia/cuda:xx-cuddnx
ARG BASE_IMAGE

# We install NVM because the node version packaged by Ubuntu is generally ancient
ARG NODE_VERSION=22.12.0

### Build Caddy with single port TLS redirect
FROM golang:1.23.4-bookworm AS caddy_builder

# Install required packages
RUN apt-get update && apt-get install -y \
    wget \
    git

# Install xcaddy for the current architecture
RUN wget -O xcaddy.deb "https://github.com/caddyserver/xcaddy/releases/download/v0.4.4/xcaddy_0.4.4_linux_$(dpkg --print-architecture).deb" && \
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

# Add some useful scripts and config files
COPY ./ROOT/ /

# Vast.ai environment variables used for Jupyter & Data sync
ENV DATA_DIRECTORY=/workspace
ENV WORKSPACE=/workspace

# Ubuntu 24.04 requires this for compatibility with our /.launch script
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
    set -euo pipefail && \
    ([ $TARGETARCH = "arm64" ] && echo "Skipping i386 architecture for ARM builds" || dpkg --add-architecture i386) && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
        software-properties-common \
        gpg-agent && \
    # For alternative Python versions
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
        # Base system utilities
        acl \
        ca-certificates \
        openssh-server \
        locales \
        lsb-release \
        curl \
        wget \
        sudo \
        moreutils \
        nano \
        less \
        jq \
        git \
        git-lfs \
        man \
        tzdata \
        # Display
        fonts-dejavu \
        fonts-freefont-ttf \
        fonts-ubuntu \
        ffmpeg \
        libgl1-mesa-glx \
        # System monitoring & debugging
        htop \
        iotop \
        strace \
        libtcmalloc-minimal4 \
        lsof \
        procps \
        psmisc \
        nvtop \
        # Development essentials
        build-essential \
        cmake \
        ninja-build \
        gdb \
        # System Python
        python3-full \
        python3-dev \
        python3-pip \
        # Network utilities
        netcat \
        net-tools \
        dnsutils \
        iproute2 \
        iputils-ping \
        traceroute \
        # File management
        rsync \
        rclone \
        zip \
        unzip \
        xz-utils \
        zstd \
        # Performance analysis
        linux-tools-common \
        # Process management
        supervisor \
        cron \
        # Required for cron logging
        rsyslog \
        # OpenCL General
        clinfo \
        pocl-opencl-icd \
        opencl-headers \
        ocl-icd-dev \
        ocl-icd-opencl-dev && \
    # Ensure TensorRT where applicable
    if [ -n "${CUDA_VERSION:-}" ]; then \
        CUDA_MAJOR_MINOR=$(echo ${CUDA_VERSION} | cut -d. -f1,2 | tr -d ".") && \
        if [ "$CUDA_MAJOR_MINOR" -ge "126" ]; then \
            apt-get update && apt-get install -y --no-install-recommends \
                libnvinfer10 \
                libnvinfer-plugin10; \
        elif [ "$CUDA_MAJOR_MINOR" -ge "121" ]; then \
            apt-get update && apt-get install -y --no-install-recommends \
                libnvinfer8 \
                libnvinfer-plugin8; \
        fi \
    fi
    # Install OpenCL Runtimes
    ARG TARGETARCH
    RUN \
    set -euo pipefail && \
        if command -v rocm-smi >/dev/null 2>&1; then \
            apt-get install -y rocm-opencl-runtime; \
        elif [ -n "${CUDA_VERSION:-}" ]; then \
            CUDA_MAJOR_MINOR=$(echo ${CUDA_VERSION} | cut -d. -f1,2 | tr -d ".") && \
            # Refer to https://docs.nvidia.com/deploy/cuda-compatibility/#id3 and set one version below to avoid driver conflicts (patch versions > driver)
            # Avoid transitional packages - They will cause NVML errors and broken nvidia-smi by bumping the version 
            if [ "${CUDA_MAJOR_MINOR}" -ge 118 ]; then \
                case "${CUDA_MAJOR_MINOR}" in \
                    "118"|"120") \
                        driver_version=470 \
                        ;; \
                    "121") \
                        driver_version=525 \
                        ;; \
                    "122") \
                        driver_version=525 \
                        ;; \
                    "123") \
                        driver_version=535 \
                        ;; \
                    "124") \
                        driver_version=535 \
                        ;; \
                    "125") \
                        driver_version=545 \
                        ;; \
                    "126") \
                        driver_version=555 \
                        ;; \
                    *) \
                        driver_version=555 \
                        ;; \
                esac \
            else \
                driver_version=390; \
            fi && \
            if [ "${TARGETARCH}" = "arm64" ] && [ "${driver_version}" -lt 510 ]; then \
                echo "No suitable libnvidia-compute package is available for arm64 with driver ${driver_version}"; \
            else \
                apt-get install -y libnvidia-compute-${driver_version}; \
            fi \
        fi && \
        apt-get clean -y
    

# Add a normal user account - Some applications don't like to run as root so we should save our users some time.  Give it unfettered access to sudo
RUN \
    set -euo pipefail && \
    groupadd -g 1001 user && \
    useradd -ms /bin/bash user -u 1001 -g 1001 && \
    echo "PATH=${PATH}" >> /home/user/.bashrc && \
    echo "user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/user && \
    sudo chmod 0440 /etc/sudoers.d/user && \
    mkdir -m 700 -p /run/user/1001 && \
    chown 1001:1001 /run/user/1001 && \
    mkdir /run/dbus && \
    mkdir /opt/workspace-internal/ && \
    chown 1001:1001 /opt/workspace-internal/ && \
    chmod g+s /opt/workspace-internal/ && \
    chmod 775 /opt/workspace-internal/ && \
    setfacl -d -m g:user:rw- /opt/workspace-internal/

# Install NVM for node version management
RUN \
    set -euo pipefail && \
    git clone https://github.com/nvm-sh/nvm.git /opt/nvm && \
    (cd /opt/nvm/ && git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`) && \
    source /opt/nvm/nvm.sh && \
    nvm install --lts && \
    echo "source /opt/nvm/nvm.sh" >> /root/.bashrc && \
    echo "source /opt/nvm/nvm.sh" >> /home/user/.bashrc

# Add the 'service portal' web app into this container to avoid needing to specify in onstart.  
# We will launch each component with supervisor - Not the standalone launch script.
COPY ./portal-aio /opt/portal-aio
COPY --from=caddy_builder /go/caddy /opt/portal-aio/caddy_manager/caddy
ARG TARGETARCH
RUN \
    set -euo pipefail && \
    apt-get install --no-install-recommends -y \
        python3.10-venv && \
    python3.10 -m venv /opt/portal-aio/venv && \
    mkdir -m 770 -p /var/log/portal && \
    chown 0:1001 /var/log/portal/ && \
    mkdir -p opt/instance-tools/bin/ && \
    /opt/portal-aio/venv/bin/pip install -r /opt/portal-aio/requirements.txt 2>&1 | tee -a /var/log/portal/portal.log && \
    wget -O /opt/portal-aio/tunnel_manager/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${TARGETARCH} && \
    chmod +x /opt/portal-aio/tunnel_manager/cloudflared && \
    # Make these portal-provided tools easily reachable
    ln -s /opt/portal-aio/caddy_manager/caddy /opt/instance-tools/bin/caddy && \
    ln -s /opt/portal-aio/tunnel_manager/cloudflared /opt/instance-tools/bin/cloudflared

# Populate the system Python environment with useful tools.  Add jupyter to speed up instance creation and install tensorboard as it is quite useful if training
# These are in the system and not the venv because we want that to be as clean as possible
RUN \
    set -euo pipefail && \
    wget -O /usr/local/share/ca-certificates/jvastai.crt https://console.vast.ai/static/jvastai_root.cer && \
    update-ca-certificates && \
    pip install --no-cache-dir \
        jupyter \
        tensorboard \
        vastai

# Install Syncthing
ARG TARGETARCH
RUN \
    set -euo pipefail && \
    SYNCTHING_VERSION="$(curl -fsSL "https://api.github.com/repos/syncthing/syncthing/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')" && \
    SYNCTHING_URL="https://github.com/syncthing/syncthing/releases/download/v${SYNCTHING_VERSION}/syncthing-linux-${TARGETARCH}-v${SYNCTHING_VERSION}.tar.gz" && \
    mkdir /opt/syncthing/ && \
    wget -O /opt/syncthing.tar.gz $SYNCTHING_URL && (cd /opt && tar -zxf syncthing.tar.gz -C /opt/syncthing/ --strip-components=1) && rm -f /opt/syncthing.tar.gz

ARG PYTHON_VERSION=3.10
ENV PYTHON_VERSION=${PYTHON_VERSION}
RUN \
    set -euo pipefail && \
    # Supplementary Python
    apt-get install --no-install-recommends -y \
        python${PYTHON_VERSION}-full \
        python${PYTHON_VERSION}-venv && \
    mkdir -p /venv && \
    # Create a virtual env - This gives us portability without sacrificing any functionality
    python${PYTHON_VERSION} -m venv /venv/main && \
    /venv/main/bin/pip install --no-cache-dir \
        wheel \
        huggingface_hub[cli] \
        ipykernel \
        ipywidgets && \
    /venv/main/bin/python -m ipykernel install \
        --name="main" \
        --display-name="Python3 (main venv)" && \
    # Re-add as default.  We don't want users accidentally installing packages in the system python
    /venv/main/bin/python -m ipykernel install \
        --name="python3" \
        --display-name="Python3 (ipykernel)" && \
    # Add a cron job to regularly backup all venvs in /venv/*
    echo "*/30 * * * * /opt/instance-tools/bin/venv-backup.sh" | crontab -

ENV PATH=/opt/instance-tools/bin:${PATH}

CMD ["entrypoint.sh"]

WORKDIR /workspace/
