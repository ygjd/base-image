import argparse
from huggingface_hub import snapshot_download
from huggingface_hub.utils import logging
import time
from requests.exceptions import ChunkedEncodingError

def download_with_retries(repo_id, local_dir, allow_patterns, max_retries=5, initial_delay=1):
    for attempt in range(max_retries):
        try:
            return snapshot_download(
                repo_id=repo_id,
                local_dir=local_dir,
                allow_patterns=allow_patterns
            )
        except ChunkedEncodingError as e:
            if attempt == max_retries - 1:
                raise
            delay = initial_delay * (2 ** attempt)  # Exponential backoff
            print(f"\nDownload interrupted. Retrying in {delay} seconds... (Attempt {attempt + 1}/{max_retries})")
            time.sleep(delay)

def main():
    parser = argparse.ArgumentParser(description='Download models from Hugging Face Hub')
    parser.add_argument('--repo', required=True, help='Hugging Face repository ID')
    parser.add_argument('--version', required=False, help='Version to download')
    
    args = parser.parse_args()
    
    # Enable verbose logging
    logging.set_verbosity_info()
    
    download_with_retries(
        repo_id=args.repo,
        local_dir="/workspace/llama.cpp/models",
        allow_patterns=[f"*{args.version}*"]
    )

if __name__ == "__main__":
    main()