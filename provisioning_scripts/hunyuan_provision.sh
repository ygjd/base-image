#!/bin/bash
# Direct provisioning script for Hunyuan on Vast.ai
# Author: Jay Hill

# Set environment
export CUDA_HOME=/usr/local/cuda
export DEBIAN_FRONTEND=noninteractive
export PYTHONPATH=/app:$PYTHONPATH
export PATH=/app:$PATH

# Clean workspace and setup
rm -rf /app
mkdir -p /app
cd /app

# Create log directory
mkdir -p /var/log/portal
touch /var/log/portal/hunyuan-ui.log

# Clone Hunyuan repository
git clone https://github.com/tencent/HunyuanVideo .

git clone https://github.com/ygjd/start.git start

# Create results directory
mkdir -p /app/results
chmod 777 /app/results

# Install basic requirements
pip install --upgrade pip
pip install -r requirements.txt

# Install PyTorch w/ CUDA 12.4 support
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu124

# Install FlashAttention and xDiT
pip install ninja
pip install xfuser==0.4.0

# Install Gradio and other dependencies
pip install gradio --no-cache-dir
pip install --force-reinstall loguru einops imageio diffusers transformers
pip install flash-attn --no-build-isolation
pip install accelerate>=0.14.0
pip install imageio[ffmpeg] imageio[pyav]

# Install remaining dependencies
pip install uvicorn fastapi pandas numpy pillow
pip install ffmpeg-python moviepy opencv-python
pip install jinja2 markdown websockets aiohttp httpx
pip install orjson pyyaml aiofiles python-multipart av

# Download models
huggingface-cli download tencent/HunyuanVideo --local-dir ./ckpts
huggingface-cli download xtuner/llava-llama-3-8b-v1_1-transformers --local-dir ./ckpts/llava-llama-3-8b-v1_1-transformers
huggingface-cli download openai/clip-vit-large-patch14 --local-dir ./ckpts/text_encoder_2

# Preprocess model
python3 /app/hyvideo/utils/preprocess_text_encoder_tokenizer_utils.py \
  --input_dir ./ckpts/llava-llama-3-8b-v1_1-transformers \
  --output_dir ./ckpts/text_encoder

# Wait for model downloads to complete ( minutes)
echo "Waiting for model downloads to complete ( .)..."
sleep 20  

# Fix NumPy/Pandas binary mismatch that can occur after waiting
pip uninstall -y numpy pandas
pip install numpy==1.24.4 pandas==2.0.3 --force-reinstall

# Reinstall critical dependencies after wait
pip install loguru einops imageio diffusers transformers
pip install flash-attn --no-build-isolation
pip install gradio --no-cache-dir
pip install accelerate>=0.14.0
pip install imageio[ffmpeg] imageio[pyav]

# Start the UI directly
cd /app
python3 gradio_server.py

