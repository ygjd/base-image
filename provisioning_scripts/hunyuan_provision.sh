#!/bin/bash
#
# Hunyuan Video Provisioning Script for Vast.ai
# Author: Jay Hill
#
# This script sets up the Hunyuan Video environment on Vast.ai
# It installs dependencies and configures the Gradio web interface

set -e  # Exit immediately if any command fails

# ----- Environment Setup -----
export CUDA_HOME=/usr/local/cuda
export DEBIAN_FRONTEND=noninteractive
export PYTHONPATH=/app:$PYTHONPATH
export PATH=/app:$PATH

echo "==============================================="
echo "Hunyuan Video Setup - Starting Installation"
echo "==============================================="

# ----- Workspace Preparation -----
echo "[1/7] Preparing workspace..."
rm -rf /app
mkdir -p /app
cd /app

# Create log directories
mkdir -p /var/log/portal
touch /var/log/portal/hunyuan-ui.log

# Create output directories
mkdir -p /app/results
mkdir -p /app/gradio_outputs
chmod 777 /app/results
chmod 777 /app/gradio_outputs

# ----- Repository Cloning -----
echo "[2/7] Cloning repositories..."
# Install git if not already available
apt-get update -y
apt-get install -y git

# Clone main repository
git clone https://github.com/tencent/HunyuanVideo .

# Clone base-image repository with support files
git clone https://github.com/ygjd/base-image.git /app/base-image

# ----- System Dependencies -----
echo "[3/7] Installing system dependencies..."
apt-get install -y \
    ffmpeg \
    libsm6 \
    libxext6 \
    libgl1-mesa-glx \
    ninja-build \
    python3-dev \
    build-essential \
    wget \
    curl

# ----- Python Dependencies -----
echo "[4/7] Installing Python dependencies..."

# Core Python setup
pip install --upgrade pip

# Install PyTorch first with CUDA support
echo "Installing PyTorch with CUDA support..."
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu124

# Install critical dependencies
echo "Installing core dependencies..."
pip install loguru==0.7.0
pip install numpy==1.24.4 pandas==2.0.3

# AI model dependencies
echo "Installing AI model dependencies..."
pip install ninja xfuser==0.4.0
pip install flash-attn --no-build-isolation
pip install accelerate>=0.14.0
pip install einops imageio diffusers transformers

# Media handling dependencies
echo "Installing media processing libraries..."
pip install ffmpeg-python moviepy opencv-python
pip install imageio[ffmpeg] imageio[pyav]

# Web serving dependencies
echo "Installing web interface dependencies..."
pip install gradio==3.50.2 --no-cache-dir
pip install uvicorn fastapi
pip install pillow jinja2 markdown websockets aiohttp httpx
pip install orjson pyyaml aiofiles python-multipart av

# Model downloading tools
echo "Installing model downloading tools..."
pip install huggingface_hub

# ----- Configuration Files -----
echo "[5/7] Setting up configuration files..."

# Copy gradio_server.py from base-image repo if it exists
if [ -f "/app/base-image/gradio_server.py" ]; then
    echo "Using gradio_server.py from base-image repository..."
    cp /app/base-image/gradio_server.py /app/
else
    echo "gradio_server.py not found in base-image repository"
    echo "Please check that the file exists in your repository"
    exit 1
fi

# ----- Model Download -----
echo "[6/7] Downloading models from Hugging Face..."
python3 -c "
from huggingface_hub import snapshot_download
import os

# Create directory
os.makedirs('./ckpts', exist_ok=True)

# Download models
print('Downloading HunyuanVideo model...')
snapshot_download(repo_id='tencent/HunyuanVideo', local_dir='./ckpts')

print('Downloading LLaVA model...')
snapshot_download(repo_id='xtuner/llava-llama-3-8b-v1_1-transformers', local_dir='./ckpts/llava-llama-3-8b-v1_1-transformers')

print('Downloading CLIP model...')
snapshot_download(repo_id='openai/clip-vit-large-patch14', local_dir='./ckpts/text_encoder_2')
"

# ----- Model Preprocessing -----
echo "Preprocessing text encoder model..."
python3 /app/hyvideo/utils/preprocess_text_encoder_tokenizer_utils.py \
  --input_dir ./ckpts/llava-llama-3-8b-v1_1-transformers \
  --output_dir ./ckpts/text_encoder

# Wait for processing to complete
sleep 5

# ----- System Verification -----
echo "[7/7] Verifying installation..."

echo "CUDA version: $(nvcc --version | grep release | awk '{print $6}' | cut -c2-)"
echo "PyTorch version: $(python3 -c 'import torch; print(torch.__version__)')"
echo "GPU information:"
python3 -c "import torch; [print(f'GPU {i}: {torch.cuda.get_device_name(i)}') for i in range(torch.cuda.device_count())]"

# Verify imports
python3 -c "
try:
    import torch
    import gradio
    import loguru
    import numpy
    import imageio
    from pathlib import Path
    print('All critical imports successful!')
except ImportError as e:
    print(f'Import error: {e}')
    exit(1)
"

echo "==============================================="
echo "Hunyuan Video Setup Complete!"
echo "==============================================="

# ----- Launch Application -----
echo "Starting Hunyuan Video UI..."
cd /app
python3 gradio_server.py
