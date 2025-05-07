from pathlib import Path
from datetime import datetime

# Try to import torch with a fallback
try:
    import torch
    has_torch = True
    logger.info(f"PyTorch imported successfully")
    
    # GPU configuration and diagnostics
    logger.info(f"CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        device_count = torch.cuda.device_count()
        logger.info(f"Available GPU count: {device_count}")
        for i in range(device_count):
            device_props = torch.cuda.get_device_properties(i)
            logger.info(f"GPU {i}: {device_props.name} with {device_props.total_memory / 1e9:.2f} GB memory")
        
        # Configure PyTorch for optimal performance
        torch.backends.cudnn.benchmark = True
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        torch.set_float32_matmul_precision('high')
except ImportError:
    logger.warning("PyTorch not available - some features may not work")
    has_torch = Falseimport os
import time
import torch
from pathlib import Path
from loguru import logger
from datetime import datetime
import gradio as gr
import random

from hyvideo.utils.file_utils import save_videos_grid
from hyvideo.config import parse_args
from hyvideo.inference import HunyuanVideoSampler
from hyvideo.constants import NEGATIVE_PROMPT

# GPU configuration and diagnostics
logger.info(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    device_count = torch.cuda.device_count()
    logger.info(f"Available GPU count: {device_count}")
    for i in range(device_count):
        device_props = torch.cuda.get_device_properties(i)
        logger.info(f"GPU {i}: {device_props.name} with {device_props.total_memory / 1e9:.2f} GB memory")
    
    # Configure PyTorch for optimal performance
    torch.backends.cudnn.benchmark = True
    torch.backends.cuda.matmul.allow_tf32 = True
    torch.backends.cudnn.allow_tf32 = True
    torch.set_float32_matmul_precision('high')

def initialize_model(model_path):
    try:
        from hyvideo.config import parse_args
        from hyvideo.inference import HunyuanVideoSampler
        
        args = parse_args()
        models_root_path = Path(model_path)
        if not models_root_path.exists():
            raise ValueError(f"`models_root` not exists: {models_root_path}")
        
        hunyuan_video_sampler = HunyuanVideoSampler.from_pretrained(models_root_path, args=args)
        return hunyuan_video_sampler
    except ImportError as e:
        logger.error(f"Failed to import required modules: {e}")
        raise

def generate_video(
    model,
    prompt,
    resolution,
    video_length,
    seed,
    num_inference_steps,
    guidance_scale,
    flow_shift,
    embedded_guidance_scale,
    fps=24,
    video_quality=23,
    use_cpu_fallback=False
):
    try:
        from hyvideo.utils.file_utils import save_videos_grid
        from hyvideo.constants import NEGATIVE_PROMPT
        
        seed = None if seed == -1 else seed
        width, height = resolution.split("x")
        width, height = int(width), int(height)
        negative_prompt = ""  # not applicable in the inference

        logger.info(f"Starting generation with resolution {width}x{height}, video length {video_length}")
        
        # If CPU fallback is enabled and GPU fails, try again with CPU
        device = None
        if use_cpu_fallback and has_torch and torch.cuda.is_available():
            try:
                device = torch.device("cuda")
                # Test GPU availability with a small tensor operation
                test_tensor = torch.zeros(1, device=device)
                del test_tensor
            except Exception as e:
                logger.warning(f"GPU test failed: {e}. Falling back to CPU")
                device = torch.device("cpu")
                
        outputs = model.predict(
            prompt=prompt,
            height=height,
            width=width, 
            video_length=video_length,
            seed=seed,
            negative_prompt=negative_prompt,
            infer_steps=num_inference_steps,
            guidance_scale=guidance_scale,
            num_videos_per_prompt=1,
            flow_shift=flow_shift,
            batch_size=1,
            embedded_guidance_scale=embedded_guidance_scale,
            device=device
        )
        
        samples = outputs['samples']
        if samples is None or len(samples) == 0:
            logger.error("No samples generated!")
            return None
            
        sample = samples[0].unsqueeze(0)
        
        save_path = os.path.join(os.getcwd(), "gradio_outputs")
        os.makedirs(save_path, exist_ok=True)
        
        time_flag = datetime.now().strftime("%Y-%m-%d-%H:%M:%S")
        video_path = f"{save_path}/{time_flag}_seed{outputs['seeds'][0]}_{outputs['prompts'][0][:100].replace('/','')}.mp4"
        
        # Add encoding parameters
        save_videos_grid(
            sample, 
            video_path, 
            fps=fps,
            codec="libx264",  # Specify codec explicitly
            quality=video_quality,  # Lower is better quality (18-28 is good range)
            pixel_format="yuv420p"  # Standard format for compatibility
        )
        
        # Verify the video file exists and has content
        if os.path.exists(video_path) and os.path.getsize(video_path) > 0:
            logger.info(f'Sample successfully saved to: {video_path}')
            
            # Clear CUDA cache after generation to prevent memory buildup
            if has_torch and torch.cuda.is_available():
                torch.cuda.empty_cache()
                
            return video_path
        else:
            logger.error(f"Video file is empty or doesn't exist: {video_path}")
            return None
            
    except Exception as e:
        logger.exception(f"Error during video generation: {str(e)}")
        
        # Clear CUDA cache on error
        if has_torch and torch.cuda.is_available():
            torch.cuda.empty_cache()
            
        return None

def create_demo(model_path, save_path):
    model = initialize_model(model_path)
    
    with gr.Blocks() as demo:
        gr.Markdown("# Hunyuan Video Generation")
        
        with gr.Row():
            with gr.Column():
                prompt = gr.Textbox(label="Prompt", value="A cat walks on the grass, realistic style.")
                with gr.Row():
                    resolution = gr.Dropdown(
                        choices=[
                            # 720p
                            ("1280x720 (16:9, 720p)", "1280x720"),
                            ("720x1280 (9:16, 720p)", "720x1280"), 
                            ("1104x832 (4:3, 720p)", "1104x832"),
                            ("832x1104 (3:4, 720p)", "832x1104"),
                            ("960x960 (1:1, 720p)", "960x960"),
                            # 540p
                            ("960x544 (16:9, 540p)", "960x544"),
                            ("544x960 (9:16, 540p)", "544x960"),
                            ("832x624 (4:3, 540p)", "832x624"), 
                            ("624x832 (3:4, 540p)", "624x832"),
                            ("720x720 (1:1, 540p)", "720x720"),
                            # Lower resolutions for compatibility
                            ("640x360 (16:9, lower res)", "640x360"),
                            ("512x512 (1:1, lower res)", "512x512"),
                        ],
                        value="1280x720",
                        label="Resolution"
                    )
                    video_length = gr.Dropdown(
                        label="Video Length",
                        choices=[
                            ("2s(65f)", 65),
                            ("5s(129f)", 129),
                        ],
                        value=129,
                    )
                num_inference_steps = gr.Slider(1, 100, value=50, step=1, label="Number of Inference Steps")
                show_advanced = gr.Checkbox(label="Show Advanced Options", value=False)
                with gr.Row(visible=False) as advanced_row:
                    with gr.Column():
                        seed = gr.Number(value=-1, label="Seed (-1 for random)")
                        guidance_scale = gr.Slider(1.0, 20.0, value=1.0, step=0.5, label="Guidance Scale")
                        flow_shift = gr.Slider(0.0, 10.0, value=7.0, step=0.1, label="Flow Shift") 
                        embedded_guidance_scale = gr.Slider(1.0, 20.0, value=6.0, step=0.5, label="Embedded Guidance Scale")
                        
                        # Add new video quality options
                        gr.Markdown("### Video Rendering Settings")
                        fps = gr.Slider(12, 30, value=24, step=1, label="FPS")
                        video_quality = gr.Slider(18, 28, value=23, step=1, label="Video Quality (lower is better)")
                        use_cpu_fallback = gr.Checkbox(label="CPU Fallback (if GPU fails)", value=False)
                        
                show_advanced.change(fn=lambda x: gr.Row(visible=x), inputs=[show_advanced], outputs=[advanced_row])
                generate_btn = gr.Button("Generate")
            
            with gr.Column():
                output = gr.Video(label="Generated Video")
                error_output = gr.Textbox(label="Status", visible=True)
        
        def wrapped_generate(*args):
            try:
                # Handle the additionalProperties error by using explicit parameters
                # Rather than unpacking all args which might cause schema issues
                prompt = args[0]
                resolution = args[1] 
                video_length = args[2]
                seed = args[3]
                num_inference_steps = args[4]
                guidance_scale = args[5]
                flow_shift = args[6]
                embedded_guidance_scale = args[7]
                fps = args[8] if len(args) > 8 else 24
                video_quality = args[9] if len(args) > 9 else 23
                use_cpu_fallback = args[10] if len(args) > 10 else False
                
                result = generate_video(
                    model, 
                    prompt, 
                    resolution, 
                    video_length, 
                    seed, 
                    num_inference_steps, 
                    guidance_scale, 
                    flow_shift, 
                    embedded_guidance_scale,
                    fps,
                    video_quality,
                    use_cpu_fallback
                )
                
                if result is None:
                    return None, "Generation failed. Check logs for details."
                return result, "Generation successful!"
            except Exception as e:
                logger.exception("Error in generation wrapper")
                return None, f"Error: {str(e)}"
        
        generate_btn.click(
            fn=wrapped_generate,
            inputs=[
                prompt,
                resolution,
                video_length,
                seed,
                num_inference_steps,
                guidance_scale,
                flow_shift,
                embedded_guidance_scale,
                fps,
                video_quality,
                use_cpu_fallback
            ],
            outputs=[output, error_output]
        )
    
    return demo

if __name__ == "__main__":
    os.environ["GRADIO_ANALYTICS_ENABLED"] = "False"
    server_name = os.getenv("SERVER_NAME", "0.0.0.0")
    server_port = int(os.getenv("SERVER_PORT", "8081"))
    args = parse_args()
    print(args)
    
    # Set environment variables for better compatibility
    os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "max_split_size_mb:128"
    os.environ["FFMPEG_BINARY"] = "ffmpeg"  # Ensure ffmpeg is found
    
    demo = create_demo(args.model_base, args.save_path)
    demo.launch(
        server_name=server_name, 
        server_port=server_port,
        share=True,  # Enable share to fix localhost access issue
        debug=True,
        show_error=True,
        enable_queue=True
    )