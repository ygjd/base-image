#!/bin/bash
# Provisioning script for Hunyuan + Gradio UI
# Author: Jay Hill
# Simplified Provisioning Script for Hunyuan + Gradio UI
# For use with VastAI PyTorch base image

# Set environment
export CUDA_HOME=/usr/local/cuda
export DEBIAN_FRONTEND=noninteractive
export PYTHONPATH=/app:$PYTHONPATH
export PATH=/app:$PATH

# Clean and prep workspace
rm -rf /app
mkdir -p /app
cd /app || exit 1

# Create log directory
mkdir -p /var/log/portal
touch /var/log/portal/hunyuan-ui.log

# Clone the official repo
git clone https://github.com/tencent/HunyuanVideo . || exit 1

# Upgrade pip and install base Python deps
pip install --upgrade pip
pip install -r requirements.txt

# Install PyTorch w/ CUDA 12.4 support
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu124

# Install FlashAttention and xDiT
pip install ninja
pip install git+https://github.com/Dao-AILab/flash-attention.git@v2.6.3 --no-build-isolation
pip install xfuser==0.4.0

# Reinstall PyTorch to ensure correct version
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124

# Install Gradio and critical dependencies with explicit versions
pip install gradio==4.19.1 --no-cache-dir
pip install loguru==0.7.2 --no-cache-dir
pip install einops==0.7.0 --no-cache-dir
pip install imageio==2.31.6 --no-cache-dir
pip install diffusers==0.26.3 --no-cache-dir
pip install transformers==4.41.1 --no-cache-dir
pip install flash-attn==2.7.4 --no-build-isolation

# Install remaining dependencies
pip install uvicorn fastapi pandas numpy pillow ffmpeg-python moviepy opencv-python
pip install jinja2 markdown websockets aiohttp httpx orjson pyyaml aiofiles python-multipart av

# Verify critical installations
pip list | grep gradio
pip list | grep loguru
pip list | grep flash-attn
pip list | grep transformers

# Download model files
huggingface-cli download tencent/HunyuanVideo --local-dir ./ckpts
huggingface-cli download xtuner/llava-llama-3-8b-v1_1-transformers --local-dir ./ckpts/llava-llama-3-8b-v1_1-transformers
huggingface-cli download openai/clip-vit-large-patch14 --local-dir ./ckpts/text_encoder_2

# Preprocess LLaVA model
cd /app
python3 /app/hyvideo/utils/preprocess_text_encoder_tokenizer_utils.py \
  --input_dir ./ckpts/llava-llama-3-8b-v1_1-transformers \
  --output_dir ./ckpts/text_encoder

# Create startup script
mkdir -p /opt/supervisor-scripts
echo '#!/bin/bash
cd /app
pip install gradio==4.19.1 loguru==0.7.2 einops==0.7.0 imageio==2.31.6 diffusers==0.26.3 transformers==4.41.1 flash-attn==2.7.4 --no-build-isolation
python3 hunyuan_ui.py >> /var/log/portal/hunyuan-ui.log 2>&1
' > /opt/supervisor-scripts/hunyuan-ui.sh
chmod +x /opt/supervisor-scripts/hunyuan-ui.sh

# Create supervisor config
mkdir -p /etc/supervisor/conf.d
echo '[program:hunyuan-ui]
command=/opt/supervisor-scripts/hunyuan-ui.sh
autostart=true
autorestart=true
startretries=5
startsecs=10
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/portal/hunyuan-ui.log
stderr_logfile=/var/log/portal/hunyuan-ui.log
priority=100
' > /etc/supervisor/conf.d/hunyuan-ui.conf

# Restart supervisor
supervisorctl reread
supervisorctl update

echo "Hunyuan Video Generation provisioning complete"
echo "The UI should be accessible at http://localhost:8081 or the public URL provided by Vast.ai"
