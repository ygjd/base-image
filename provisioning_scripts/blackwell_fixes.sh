#!/bin/bash

# NVIDIA only

if ! command -v nvidia-smi &> /dev/null; then
    exit 0
fi

# Only apply on Blackwell architecture
if ! nvidia-smi -a | grep -i "Blackwell" > /dev/null; then
    exit 0
fi

if [[ "$CUDA_VERSION" != "12.8"* ]]; then
    echo "Atempting Blackwell architecture fix for non CUDA 12.8 Docker image - See https://docs.vast.ai/rtx-5090-guide for further information" 
    NCCL_VERSION=$(dpkg-query -W -f='${Version}' libnccl2 2>/dev/null | cut -d'-' -f1 || echo "0.0.0")
    if dpkg --compare-versions "$NCCL_VERSION" lt "2.26.2"; then
        echo "Updating NCCL to version 2.26.2-1+cuda12.8"
        apt-get -y update
        apt-get install -y --allow-change-held-packages libnccl2=2.26.2-1+cuda12.8 libnccl-dev=2.26.2-1+cuda12.8
    fi
fi

# Only apply the PyTorch fix if we have PyTorch already
if [[ -n $PYTORCH_VERSION ]]; then
    echo "Attempting to fix PyTorch for Blackwell architecture for non-CUDA 12.8 image"
    echo "Uninstalling existing Torch setup"
    /venv/main/bin/pip uninstall -y torch torchvision torchaudio xformers
    echo "Installing latest nightly PyTorch"
    # 2.7 is at RC - Use that for now, but we will have no xformers
    /venv/main/bin/pip install --no-cache-dir --pre \
        torch==2.7.0.dev20250312+cu128 \
        torchvision==0.22.0.dev20250312+cu128 \
        torchaudio==2.6.0.dev20250312+cu128 \
        --upgrade-strategy only-if-needed --index-url https://download.pytorch.org/whl/nightly/cu128
    # If that failed, PyTorch may have released a stable build and removed the nightly
    if [[ $? != 0 ]]; then
        /venv/main/bin/pip install --no-cache-dir --pre \
            torch==2.7.0 \
            torchvision \
            torchaudio \
            --upgrade-strategy only-if-needed --index-url https://download.pytorch.org/whl/cu128
    fi
    echo "Replacing /venv/main/lib/python${PYTHON_VERSION}/site-packages/nvidia/nccl/lib/libnccl.so.2"
    cp /usr/lib/x86_64-linux-gnu/libnccl.so.2 "/venv/main/lib/python${PYTHON_VERSION}/site-packages/nvidia/nccl/lib/"
fi

echo "Fixes applied.  Please use cu128 docker images wherever possible when using Blackwell GPUs - See https://docs.vast.ai/rtx-5090-guide for further information"
