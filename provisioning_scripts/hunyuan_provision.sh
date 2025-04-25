#!/bin/bash
# Set environment
export CUDA_HOME=/usr/local/cuda
export DEBIAN_FRONTEND=noninteractive
export PYTHONPATH=/app:$PYTHONPATH
export PATH=/app:$PATH

# Clean and prep workspace
rm -rf /app && mkdir -p /app && cd /app || exit 1

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

# Ensure PyTorch and torchvision versions - critical for compatibility
pip uninstall -y torch torchvision
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124

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