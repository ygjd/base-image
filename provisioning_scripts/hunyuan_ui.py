
with open('/workspace/app.py', 'w') as f:
    f.write('''
import gradio as gr
import os
import subprocess
import time
from datetime import datetime
import uuid

# Configuration paths
OUTPUT_DIR = "results"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def generate_video(
    prompt,
    resolution,
    video_length,
    infer_steps,
    use_cpu_offload,
    use_fp8,
    flow_reverse,
    progress=gr.Progress()
):
    """Generate video with HunyuanVideo"""
    if not prompt.strip():
        return None, "Error: Please enter a prompt."
        
    # Create timestamp for output directory
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = os.path.join(OUTPUT_DIR, timestamp)
    os.makedirs(output_dir, exist_ok=True)
    
    # Parse resolution
    width, height = resolution.split('x')
    
    # Build the command with known working parameters
    cmd = [
        "python3", "sample_video.py",
        "--video-size", height, width,
        "--video-length", str(video_length),
        "--infer-steps", str(infer_steps),
        "--prompt", prompt,
        "--text-encoder", "clipL",
        "--tokenizer", "clipL",
        "--text-encoder-2", "clipL",
        "--tokenizer-2", "clipL",
        "--text-len", "77",
        "--text-len-2", "77",
        "--save-path", output_dir
    ]
    
    if use_fp8:
        cmd.append("--use-fp8")
    
    if flow_reverse:
        cmd.append("--flow-reverse")
        
    if use_cpu_offload:
        cmd.append("--use-cpu-offload")
    
    # Execute the command
    progress(0.05, desc="Starting video generation...")
    
    # Log the command for debugging
    cmd_str = ' '.join(cmd)
    print(f"Executing command: {cmd_str}")
    
    try:
        process = subprocess.Popen(
            cmd, 
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True
        )
        
        # Stream and capture output
        output_text = "Starting generation (this may take up to 40 minutes for the first run)...\\n"
        output_text += "Initial model loading takes ~40 minutes. Subsequent runs will be faster.\\n\\n"
        yield output_text, None
        
        for line in process.stdout:
            output_text += line
            # Show progress updates to the user
            progress_updates = [
                "Loading model", "Initializing", "Creating", "Generating", 
                "Processing", "Sampling", "Step", "Frame"
            ]
            for update in progress_updates:
                if update in line:
                    progress_val = min(0.05 + (0.9 * process.stdout.line_no / 100), 0.95)
                    progress(progress_val, desc=f"Generating: {line.strip()}")
                    break
            yield output_text, None
        
        # Wait for completion
        process.wait()
        progress(0.95, desc="Processing output...")
        
        if process.returncode != 0:
            return output_text + "\\n\\nError during generation.", None
        
        # Look for the generated video file
        video_files = []
        for root, dirs, files in os.walk(output_dir):
            for file in files:
                if file.endswith('.mp4'):
                    video_files.append(os.path.join(root, file))
        
        if video_files:
            # Sort by creation time to get the most recent
            video_files.sort(key=os.path.getmtime, reverse=True)
            progress(1.0, desc="Complete!")
            return output_text + "\\n\\nGeneration complete!", video_files[0]
        else:
            return output_text + "\\n\\nNo video file was generated.", None
            
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        return output_text + f"\\n\\nError: {str(e)}\\n{error_details}", None

# Create the Gradio interface
with gr.Blocks(title="HunyuanVideo Generator") as app:
    gr.Markdown("# HunyuanVideo Generator")
    gr.Markdown("""
    Generate realistic videos from text prompts using Tencent's HunyuanVideo model.
    
    **IMPORTANT**: 
    - Initial model loading takes ~40 minutes
    - Video generation is GPU-intensive and will incur usage costs
    """)
    
    with gr.Tab("Generate Video"):
        with gr.Row():
            with gr.Column(scale=1):
                prompt = gr.Textbox(
                    label="Prompt",
                    placeholder="Cat walking through grass",
                    lines=3
                )
                
                resolution = gr.Radio(
                    ["1280x720", "720x1280", "960x544", "544x960", "960x960", "720x720"],
                    label="Resolution",
                    value="1280x720",
                    info="Width x Height - Select appropriate aspect ratio"
                )
                
                with gr.Row():
                    video_length = gr.Dropdown(
                        [33, 65, 97, 129],
                        label="Video Length",
                        value=129,
                        info="Must be a number where (length-1) is divisible by 4"
                    )
                    
                    infer_steps = gr.Slider(
                        minimum=10,
                        maximum=50,
                        step=10,
                        value=50,
                        label="Inference Steps",
                        info="Higher values = better quality but slower"
                    )
                
                with gr.Accordion("Advanced Options", open=False):
                    use_cpu_offload = gr.Checkbox(
                        label="Use CPU Offload",
                        value=True,
                        info="Offload unused layers to CPU (reduces GPU memory usage)"
                    )
                    
                    use_fp8 = gr.Checkbox(
                        label="Use FP8",
                        value=False,
                        info="Use FP8 precision (reduces memory usage, may affect quality)"
                    )
                    
                    flow_reverse = gr.Checkbox(
                        label="Flow Reverse",
                        value=True,
                        info="Enable flow reverse (recommended)"
                    )
                
                generate_btn = gr.Button("Generate Video", variant="primary")
                cancel_btn = gr.Button("Cancel", variant="stop")
            
            with gr.Column(scale=1):
                with gr.Box():
                    output_video = gr.Video(label="Generated Video")
                    output_log = gr.Textbox(
                        label="Generation Log",
                        interactive=False,
                        lines=15,
                        autoscroll=True
                    )
    
    # Examples
    with gr.Accordion("Example Prompts", open=False):
        gr.Examples(
            examples=[
                ["Cat walking through grass"],
                ["A dog playing in a sunny park"],
                ["Ocean waves crashing on a beach at sunset"],
                ["Time lapse of a flower blooming"],
                ["Drone shot of a forest in autumn"]
            ],
            inputs=prompt,
            outputs=[],
            fn=None
        )
    
    # Usage notes
    with gr.Accordion("Usage Notes", open=False):
        gr.Markdown("""
        ## Tips for Best Results
        
        - **First Run**: The first generation will take ~40 minutes as models load
        - **Simple Prompts**: Keep prompts concise and clear
        - **Resolution**: 1280x720 or 720x1280 work well for most cases
        - **Video Length**: Longer videos (129 frames) give smoother results
        - **Inference Steps**: Higher values (50) give better quality but take longer
        
        ## Billing and Resources
        
        This tool uses GPU resources and will incur costs on vast.ai for the duration of video generation. 
        A typical generation can take 30-60 minutes including model loading time.
        """)
    
    # Set up event handlers
    generate_event = generate_btn.click(
        generate_video,
        inputs=[
            prompt,
            resolution,
            video_length,
            infer_steps,
            use_cpu_offload,
            use_fp8,
            flow_reverse
        ],
        outputs=[output_log, output_video]
    )
    
    cancel_btn.click(
        fn=None,
        inputs=None,
        outputs=None,
        cancels=[generate_event]
    )

# Launch the app - adapt to vast.ai port forwarding
if __name__ == "__main__":
    try:
        # Try to launch on port 7860 (common Gradio port)
        app.launch(server_name="0.0.0.0", server_port=7860, share=True)
    except OSError:
        # If that port is busy, try the alternate port
        try:
            app.launch(server_name="0.0.0.0", server_port=8080, share=True)
        except OSError:
            # Let Gradio choose an available port
            app.launch(server_name="0.0.0.0", share=True)
''')
