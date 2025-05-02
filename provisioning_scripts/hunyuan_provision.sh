#!/bin/bash
# Provisioning script for Hunyuan + Gradio UI
# Author: Jay Hill
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
pip install xfuser==0.4.0

# Reinstall PyTorch to ensure correct version
pip uninstall -y torch torchvision
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124

# Install Gradio BEFORE other dependencies to ensure it's properly registered
pip install gradio --no-cache-dir

# Install specific dependencies with --force-reinstall to ensure they're properly installed
pip install --force-reinstall loguru einops imageio diffusers transformers
pip install flash-attn --no-build-isolation

# Install accelerate for CPU offloading
pip install accelerate>=0.14.0

# Install imageio with ffmpeg and pyav plugins - this fixes the video saving issue
pip install imageio[ffmpeg] imageio[pyav]

# Install remaining dependencies
pip install uvicorn fastapi pandas numpy pillow
pip install ffmpeg-python moviepy opencv-python
pip install jinja2 markdown websockets aiohttp httpx
pip install orjson pyyaml aiofiles python-multipart av

# Verify critical installations
pip list | grep gradio || echo "CRITICAL ERROR: gradio not installed"
pip list | grep loguru || echo "CRITICAL ERROR: loguru not installed"

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

# Create file to signal provisioning is complete
touch /app/.provisioning_complete

# Create supervisor startup script
mkdir -p /opt/supervisor-scripts
echo '#!/bin/bash
# Wait until provisioning is fully complete
while [ ! -f "/app/.provisioning_complete" ]; do
  echo "Waiting for provisioning to complete..." >> /var/log/portal/hunyuan-ui.log
  sleep 30
done

cd /app
# Force install any missing packages on startup if needed
pip install gradio loguru einops imageio diffusers transformers accelerate>=0.14.0 > /dev/null 2>&1
pip install flash-attn --no-build-isolation > /dev/null 2>&1
pip install imageio[ffmpeg] imageio[pyav] > /dev/null 2>&1

# Only start the UI after provisioning is complete
python3 hunyuan_ui.py >> /var/log/portal/hunyuan-ui.log 2>&1
' > /opt/supervisor-scripts/hunyuan-ui.sh
chmod +x /opt/supervisor-scripts/hunyuan-ui.sh

# Create supervisor startup script
mkdir -p /opt/supervisor-scripts
echo '#!/bin/bash
# Wait until provisioning is fully complete
while [ ! -f "/app/.provisioning_complete" ]; do
  echo "Waiting for provisioning to complete..." >> /var/log/portal/hunyuan-ui.log
  sleep 30
done

cd /app
# Force install packages in the EXACT same Python environment that will run the UI
/usr/bin/python3 -m pip install loguru einops imageio diffusers transformers
/usr/bin/python3 -m pip install flash-attn --no-build-isolation
/usr/bin/python3 -m pip install gradio --no-cache-dir
/usr/bin/python3 -m pip install accelerate>=0.14.0
/usr/bin/python3 -m pip install imageio[ffmpeg] imageio[pyav]

# Create results directory if it doesn't exist
mkdir -p /app/results
chmod 777 /app/results

# Overwrite the supervisor script with exactly one line
echo "/usr/bin/python3 hunyuan_ui.py >> /var/log/portal/hunyuan-ui.log 2>&1" \
  > /opt/supervisor-scripts/hunyuan-ui.sh
chmod +x /opt/supervisor-scripts/hunyuan-ui.sh

# Restart supervisor
supervisorctl reread
supervisorctl update

echo "HunyuanVideo UI has been set up and will start automatically after provisioning"
echo "The UI should be accessible at http://localhost:8081 or the public URL provided by Vast.ai"

# Re installation
# Add this to the end of your provisioning script
cat > /app/ensure_packages.py << ENDSCRIPT
import sys
import time
import subprocess
import importlib
import os

def check_package(package):
    try:
        importlib.import_module(package)
        print(f"✓ {package} is installed")
        return True
    except ImportError:
        print(f"✗ {package} is not installed")
        return False

# Packages to check
packages = ["loguru", "gradio", "einops", "imageio", "diffusers", "transformers", "flash_attn", "accelerate"]

# Install packages function
def install_packages():
    subprocess.run(["pip", "install", "loguru", "gradio", "einops", "imageio", "diffusers", "transformers"])
    subprocess.run(["pip", "install", "flash-attn", "--no-build-isolation"])
    subprocess.run(["pip", "install", "accelerate>=0.14.0"])
    subprocess.run(["pip", "install", "imageio[ffmpeg]", "imageio[pyav]"])

# Try for 30 minutes maximum (30 attempts with 1 minute wait)
for attempt in range(30):
    print(f"Attempt {attempt+1}/30 to install packages")
    
    # Install all packages
    install_packages()
    
    # Check if all packages are installed
    missing = []
    for pkg in packages:
        if not check_package(pkg.replace('-', '_')):
            missing.append(pkg)
    
    # If all packages are installed, start the server
    if not missing:
        print("All packages installed successfully!")
        
        # Check if server file exists
        if os.path.exists("/app/gradio_server.py"):
            print("Starting Gradio server...")
            subprocess.run("cd /app && python3 gradio_server.py", shell=True)
            break
        elif os.path.exists("/app/hunyuan_ui.py"):
            print("Starting Hunyuan UI...")
            subprocess.run("cd /app && python3 hunyuan_ui.py", shell=True)
            break
        else:
            print("Could not find server script. Looking for alternatives...")
            # Try to find any gradio script
            server_scripts = subprocess.run("find /app -name '*gradio*.py' -o -name '*ui.py'", shell=True, capture_output=True, text=True).stdout.strip().split('\n')
            if server_scripts and server_scripts[0]:
                script = server_scripts[0]
                print(f"Found alternative script: {script}")
                subprocess.run(f"cd /app && python3 {os.path.basename(script)}", shell=True)
                break
            else:
                print("No server scripts found")
    
    print(f"Missing packages: {missing}")
    print("Waiting 60 seconds before trying again...")
    time.sleep(60)
ENDSCRIPT

# Make the script executable and run it
chmod +x /app/ensure_packages.py
python3 /app/ensure_packages.py
