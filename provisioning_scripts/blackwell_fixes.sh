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
    NCCL_VERSION=$(dpkg-query -W -f='${Version}' libnccl2 2>/dev/null | cut -d'-' -f1 || echo "0.0.0")
    if dpkg --compare-versions "$NCCL_VERSION" lt "2.26.2"; then
        apt-get -y update
        apt-get install -y --allow-change-held-packages libnccl2=2.26.2-1+cuda12.8 libnccl-dev=2.26.2-1+cuda12.8
        cp /usr/lib/x86_64-linux-gnu/libnccl.so.2 "/venv/main/lib/python${PYTHON_VERSION}/site-packages/nvidia/nccl/lib/"
    fi
fi

# Only apply the PyTorch fix if we have PyTorch already
if [[ -n $PYTORCH_VERSION ]]; then
    echo "Attempting to fix PyTorch for Blackwell architecture for non-CUDA 12.8 image"
    echo "Uninstalling existing Torch setup"
    /venv/main/bin/pip uninstall -y torch torchvision torchaudio xformers
    echo "Installing latest nightly PyTorch"
    # 2.7 is at RC - Use that for now, but we will have no xformers
    /venv/main/bin/pip install --pre torch'<2.8' torchvision torchaudio --upgrade-strategy only-if-needed --index-url https://download.pytorch.org/whl/nightly/cu128
fi

echo "Fixes applied.  Please use cu128 docker images wherever possible"
