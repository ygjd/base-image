#!/bin/bash
# Provisioning script for Hunyuan + Gradio UI
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

# Install specific dependencies you mentioned
pip install loguru einops imageio diffusers transformers

# Install Gradio BEFORE other dependencies to ensure it's properly registered
pip install gradio --no-cache-dir

# Install specific dependencies with --force-reinstall to ensure they're properly installed
pip install --force-reinstall loguru einops imageio diffusers transformers

# Install flash-attn without version specification - this was the working approach
pip install flash-attn --no-build-isolation

# Install accelerate for CPU offloading
pip install accelerate>=0.14.0

# Install remaining dependencies
pip install uvicorn fastapi pandas numpy pillow
pip install ffmpeg-python moviepy opencv-python
pip install jinja2 markdown websockets aiohttp httpx
pip install orjson pyyaml aiofiles python-multipart av

# Verify critical installations
pip list | grep gradio || echo "CRITICAL ERROR: gradio not installed"
pip list | grep loguru || echo "CRITICAL ERROR: loguru not installed"
pip list | grep flash-attn || echo "CRITICAL ERROR: flash-attn not installed"
pip list | grep accelerate || echo "CRITICAL ERROR: accelerate not installed"

# Download core HunyuanVideo model (transformers + vae)
huggingface-cli download tencent/HunyuanVideo --local-dir ./ckpts

# Download LLaVA model for llm encoder (text_encoder)
huggingface-cli download xtuner/llava-llama-3-8b-v1_1-transformers --local-dir ./ckpts/llava-llama-3-8b-v1_1-transformers

# Download CLIP model into text_encoder_2 folder
huggingface-cli download openai/clip-vit-large-patch14 --local-dir ./ckpts/text_encoder_2

# Preprocess LLaVA model into usable text_encoder folder
cd /app
python3 /app/hyvideo/utils/preprocess_text_encoder_tokenizer_utils.py \
  --input_dir ./ckpts/llava-llama-3-8b-v1_1-transformers \
  --output_dir ./ckpts/text_encoder

# Create startup script
mkdir -p /opt/supervisor-scripts
echo '#!/bin/bash
# Wait for any remaining provisioning
while [ -f "/.provisioning" ]; do
  echo "HunyuanVideo UI startup paused until provisioning completes" >> /var/log/portal/hunyuan-ui.log
  sleep 10
done

cd /app
# Force install any missing packages on startup if needed - using the approach that worked
pip install gradio loguru einops imageio diffusers transformers accelerate>=0.14.0 > /dev/null 2>&1
pip install flash-attn --no-build-isolation > /dev/null 2>&1
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

# Create provisioning marker
touch /.provisioning

# Restart supervisor
supervisorctl reread
supervisorctl update

# Remove provisioning marker
rm -f /.provisioning

echo "Hunyuan Video Generation provisioning complete"
echo "The UI should be accessible at http://localhost:8081 or the public URL provided by Vast.ai"
