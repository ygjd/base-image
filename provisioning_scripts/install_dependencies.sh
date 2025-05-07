#!/bin/bash
# Install script to ensure all dependencies are properly installed

set -e  # Exit on error

echo "Installing necessary dependencies..."

# Install basic system packages
apt-get update
apt-get install -y ffmpeg python3-pip

# Install Python dependencies
pip install --upgrade pip

# Install core dependencies first to avoid conflicts
pip install loguru torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu124
pip install numpy==1.24.4 pandas==2.0.3

# Install Gradio and web server dependencies
pip install gradio==3.50.2 fastapi uvicorn

# Install video processing dependencies
pip install ffmpeg-python moviepy imageio[ffmpeg] imageio[pyav]

# Install AI model dependencies
pip install accelerate>=0.14.0 diffusers transformers

# Install any remaining dependencies from requirements.txt if it exists
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
fi

echo "Dependencies installation complete!"
