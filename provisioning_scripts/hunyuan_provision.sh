#!/bin/bash
# Direct provisioning script for Hunyuan on Vast.ai
# Author: Jay Hill
# Enhanced by Claude

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
echo "Cloning repositories..."
git clone https://github.com/tencent/HunyuanVideo .
git clone https://github.com/ygjd/start.git start

# Run the dependency installation script
echo "Installing dependencies..."
chmod +x /app/start/install_dependencies.sh
/app/start/install_dependencies.sh

# Create additional directories if needed
mkdir -p /app/results
mkdir -p /app/gradio_outputs
chmod 777 /app/results
chmod 777 /app/gradio_outputs

# Copy the improved gradio_server.py file
echo "Setting up the Gradio server..."
cp /app/start/gradio_server.py /app/

# Download models
echo "Downloading models from Hugging Face..."
huggingface-cli download tencent/HunyuanVideo --local-dir ./ckpts
huggingface-cli download xtuner/llava-llama-3-8b-v1_1-transformers --local-dir ./ckpts/llava-llama-3-8b-v1_1-transformers
huggingface-cli download openai/clip-vit-large-patch14 --local-dir ./ckpts/text_encoder_2

# Preprocess model
echo "Preprocessing text encoder..."
python3 /app/hyvideo/utils/preprocess_text_encoder_tokenizer_utils.py \
  --input_dir ./ckpts/llava-llama-3-8b-v1_1-transformers \
  --output_dir ./ckpts/text_encoder

# Wait for model downloads to complete
echo "Waiting for model downloads to complete..."
sleep 20  

# Print configuration information
echo "==============================================="
echo "Hunyuan Video Setup Complete"
echo "==============================================="
echo "CUDA version: $(nvcc --version | grep release | awk '{print $6}' | cut -c2-)"
echo "PyTorch version: $(python3 -c 'import torch; print(torch.__version__)')"
echo "GPU information:"
python3 -c "import torch; [print(f'GPU {i}: {torch.cuda.get_device_name(i)}') for i in range(torch.cuda.device_count())]"
echo "==============================================="

# Start the UI
echo "Starting Hunyuan Video UI..."
cd /app
python3 gradio_server.py
