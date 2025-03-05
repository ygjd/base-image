from fastapi import FastAPI, Request, HTTPException
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, StreamingResponse, RedirectResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from typing import Optional, List
from collections import deque
import yaml
import json
import httpx
import asyncio
import aiofiles
import os
import io
import zipfile
from datetime import datetime
import re
import time
import ipaddress
import subprocess
import GPUtil
import psutil
import numpy as np

tunnel_manager=os.environ.get("TUNNEL_MANAGER", "http://localhost:11112")

app = FastAPI()

tail_directory = "/var/log/portal/"
client_queues = {}
log_buffers = {}
log_monitor = None 
log_tasks = {}
MAX_LINES = 600  # Maximum lines to keep in buffer
# Track all active tasks for easy cancellation

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

def get_scheme():
    if os.environ.get("ENABLE_HTTPS", "false").lower() != "true":
        scheme = "http"
    else:
        scheme = "https"
    return scheme

def load_config():
    yaml_path = '/etc/portal.yaml'
    
    # Wait until the file exists - caddy-manager handles config writing
    while not os.path.exists(yaml_path):
        print(f"Waiting for {yaml_path} to appear...")
        time.sleep(1)

    with open(yaml_path, 'r') as file:
        config_applications = yaml.safe_load(file)['applications']
        return hydrate_applications(config_applications)

def hydrate_applications(applications):
    for app_name, app in applications.items():
        hostname = app["hostname"]
        external_port = app["external_port"]
        internal_port = app["internal_port"]
        if external_port == internal_port and internal_port == 8080:
            scheme = "https"
        else:
            scheme = get_scheme()
        applications[app_name]["target_url"] = f'{scheme}://{hostname}:{external_port}'
        applications[app_name]["mapped_port"] = os.environ.get(f'VAST_TCP_PORT_{external_port}', "")
    return applications

def strip_port(host):
    return host.split(':')[0]

def get_instance_properties():
    return {
        "id": os.environ.get("CONTAINER_ID",""),
        "gpu": get_gpu_info()
    }

def get_gpu_info():
    """Get formatted GPU information for both NVIDIA and AMD GPUs"""
    gpu_models = {}
    
    # Try to get NVIDIA GPUs
    try:
        nvidia_gpus = GPUtil.getGPUs()
        for gpu in nvidia_gpus:
            if gpu.name in gpu_models:
                gpu_models[gpu.name] += 1
            else:
                gpu_models[gpu.name] = 1
    except Exception:
        pass
    
    # Try to get AMD GPUs
    try:
        rocm_gpus = get_rocm_gpus()
        for gpu in rocm_gpus:
            if gpu.name in gpu_models:
                gpu_models[gpu.name] += 1
            else:
                gpu_models[gpu.name] = 1
    except Exception:
        pass
    
    # Check if any GPUs are available
    if not gpu_models:
        return "No GPU detected"
    
    # Format the output
    result = []
    for name, count in gpu_models.items():
        if count > 1:
            result.append(f"{count}× {name}")
        else:
            result.append(name)
    
    return ", ".join(result)

def get_rocm_gpus():
    """Get AMD GPU information using rocm-smi command line tool"""
    try:
        # Check if rocm-smi is available
        rocm_available = subprocess.run(
            ['which', 'rocm-smi'], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        ).returncode == 0
        
        if not rocm_available:
            return []
        
        # First get GPU info with memory and usage
        result = subprocess.run(
            ['rocm-smi', '--showmeminfo', 'vram', '--showuse', '--json'], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE, 
            text=True
        )
        
        if result.returncode != 0:
            return []
        
        # Parse JSON output for memory and usage
        rocm_data = json.loads(result.stdout)
        
        # Get additional GPU info including name
        name_result = subprocess.run(
            ['rocm-smi', '--showproductname', '--json'], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE, 
            text=True
        )
        
        # Parse GPU name data if available
        gpu_names = {}
        if name_result.returncode == 0:
            try:
                name_data = json.loads(name_result.stdout)
                for card_id, card_data in name_data.items():
                    if isinstance(card_data, dict):
                        # Try to construct a meaningful name from available fields
                        vendor = card_data.get('Card Vendor', '').split('[')[-1].split(']')[0] if '[' in card_data.get('Card Vendor', '') else card_data.get('Card Vendor', '')
                        sku = card_data.get('Card SKU', '')
                        gfx = card_data.get('GFX Version', '')
                        
                        if vendor and sku:
                            gpu_names[card_id] = f"{vendor} {sku} ({gfx})"
                        elif vendor:
                            gpu_names[card_id] = f"{vendor} GPU"
                        else:
                            gpu_names[card_id] = "AMD GPU"
            except:
                pass
        
        gpus = []
        
        for card_id, card_data in rocm_data.items():
            if not isinstance(card_data, dict):
                continue
                
            # Create a GPU object similar to GPUtil's structure
            gpu = type('', (), {})()
            gpu.id = int(card_id.replace('card', ''))
            
            # Set GPU name from the name data if available, otherwise use a default
            gpu.name = gpu_names.get(card_id, 'AMD GPU')
            
            # Extract memory info based on the actual output format
            gpu.memoryTotal = int(card_data.get('VRAM Total Memory (B)', 0))
            gpu.memoryTotal_mb = round(gpu.memoryTotal / (1024 * 1024), 2)  # Convert to MB
            
            gpu.memoryUsed = int(card_data.get('VRAM Total Used Memory (B)', 0))
            gpu.memoryUsed_mb = round(gpu.memoryUsed / (1024 * 1024), 2)  # Convert to MB
            
            # Extract GPU utilization
            gpu_busy = card_data.get('GPU use (%)', 0)
            try:
                gpu.load = float(gpu_busy) / 100.0 if isinstance(gpu_busy, (int, float, str)) else 0
            except (ValueError, TypeError):
                gpu.load = 0
                
            gpus.append(gpu)
            
        return gpus
    except Exception as e:
        print(f"Error getting ROCm GPU info: {str(e)}")
        return []
    
def is_in_container():
    """Check if we're running inside a container"""
    return os.path.exists('/sys/fs/cgroup/memory/memory.limit_in_bytes') or os.path.exists('/sys/fs/cgroup/memory.max')

def get_container_memory_limit():
    """Get memory limit allocated to the container"""
    try:
        # cgroups v1
        with open('/sys/fs/cgroup/memory/memory.limit_in_bytes', 'r') as f:
            limit = int(f.read().strip())
            # Very large values typically indicate no limit
            return limit if limit < 10**15 else None
    except:
        try:
            # cgroups v2
            with open('/sys/fs/cgroup/memory.max', 'r') as f:
                value = f.read().strip()
                if value == 'max':
                    return None
                return int(value)
        except:
            return None

def get_container_memory_usage():
    """Get current memory usage of the container"""
    try:
        # cgroups v1
        with open('/sys/fs/cgroup/memory/memory.usage_in_bytes', 'r') as f:
            return int(f.read().strip())
    except:
        try:
            # cgroups v2
            with open('/sys/fs/cgroup/memory.current', 'r') as f:
                return int(f.read().strip())
        except:
            return None

def get_container_memory_stats():
    """Get detailed memory stats for container including total, used and percentage"""
    if not is_in_container():
        # Not in a container, return None to fall back to psutil
        return None
        
    limit = get_container_memory_limit()
    usage = get_container_memory_usage()
    
    if limit is None or usage is None:
        return None
        
    # Calculate percentage
    percent = (usage / limit) * 100
    
    return {
        'total': limit,
        'used': usage,
        'percent': percent
    }


templates.env.filters["strip_port"] = strip_port

tunnels = {}
tunnel_api_timeout=httpx.Timeout(connect=5.0, read=30.0, write=5.0, pool=5.0)

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request, token: Optional[str] = None):
    if token is not None:
        return RedirectResponse(url="/", status_code=302)

    await set_external_ip(request.headers.get("X-Forwarded-Host"))
    return templates.TemplateResponse("index.html", {
        "request": request,
        "instance": get_instance_properties(),
        })

@app.get("/get-applications")
async def get_applications(request: Request):
    applications = load_config()
    auth_token = request.cookies.get(f"" + os.environ.get('VAST_CONTAINERLABEL') + "_auth_token")
    for app_name, app in applications.items():
        separator = '&' if '?' in app["open_path"] else '?'
        app["open_path"] += f"{separator}token={auth_token}"

    return JSONResponse(applications)

@app.get("/get-direct-url/{port}")
async def get_direct_url(port: int):
    url = f"{tunnel_manager}/get-direct-url/{port}"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            result = response.json()
            return result
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                raise HTTPException(status_code=404, detail=f"Direct URL unavailable")
        except httpx.HTTPError as e:
            # No stack trace in the live application
            raise HTTPException(status_code=500, detail=f"Error communicating with the API")
        except:
            raise HTTPException(status_code=500, detail=f"Unhandled error response from API")

@app.get("/get-existing-quick-tunnel/{target_url:path}")
async def get_existing_quick_tunnel(target_url: str):
    url = f"{tunnel_manager}/get-quick-tunnel-if-exists/{target_url}"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            result = response.json()
            return HTMLResponse(result['tunnel_url'])
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                raise HTTPException(status_code=404, detail=f"Tunnel not found")
        except httpx.HTTPError as e:
            # No stack trace in the live application
            raise HTTPException(status_code=500, detail=f"Error communicating with the API")
        except:
            raise HTTPException(status_code=500, detail=f"Unhandled error response from API")
        
@app.get("/get-existing-named-tunnel/{port}")
async def get_existing_named_tunnel(port: int):
    url = f"{tunnel_manager}/get-named-tunnel/{port}"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            result = response.json()
            return HTMLResponse(result['tunnel_url'])
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                raise HTTPException(status_code=404, detail=f"Tunnel not found")
        except httpx.HTTPError as e:
            # No stack trace in the live application
            raise HTTPException(status_code=500, detail=f"Error communicating with the API")
        except:
            raise HTTPException(status_code=500, detail=f"Unhandled error response from API")
        
@app.get("/get-all-quick-tunnels")
async def get_all_quick_tunnels():
    url = f"{tunnel_manager}/get-all-quick-tunnels"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            result = response.json()
            return result
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                raise HTTPException(status_code=404, detail=f"Tunnel not found")
        except httpx.HTTPError as e:
            # No stack trace in the live application
            raise HTTPException(status_code=500, detail=f"Error communicating with the API")
        except:
            raise HTTPException(status_code=500, detail=f"Unhandled error response from API")
        

@app.get("/get-named-tunnels")
async def get_named_tunnels():
    url = f"{tunnel_manager}/get-named-tunnels"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            result = response.json()
            return result
        except httpx.HTTPStatusError as e:
            if e.response.status_code in [404, 500]:
                raise HTTPException(status_code=404, detail=f"Tunnel config not found")
        except httpx.HTTPError as e:
            # No stack trace in the live application
            raise HTTPException(status_code=500, detail=f"Error communicating with the API")
        except:
            raise HTTPException(status_code=500, detail=f"Unhandled error response from API")


@app.post("/start-quick-tunnel/{target_url:path}")
async def start_quick_tunnel(target_url: str):  
    url = f"{tunnel_manager}/get-quick-tunnel/{target_url}"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            result = response.json()
            return result
        except httpx.HTTPError as e:
            # No stack trace in the live application
            raise HTTPException(status_code=500, detail=f"Error communicating with the API")
        except:
            raise HTTPException(status_code=500, detail=f"Unhandled error response from API")

@app.post("/stop-quick-tunnel/{target_url:path}")
async def stop_quick_tunnel(target_url: str):
    url = f"{tunnel_manager}/stop-quick-tunnel/{target_url}"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.post(url)
            response.raise_for_status()
            result = response.json()
            return result
        except httpx.HTTPError as e:
            raise HTTPException(status_code=500, detail=f"Error communicating with the API: {str(e)}")

@app.post("/refresh-quick-tunnel/{target_url:path}")
async def refresh_quick_tunnel(target_url: str):
    url = f"{tunnel_manager}/refresh-quick-tunnel/{target_url}"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.post(url)
            response.raise_for_status()
            result = response.json()
            return result
        except httpx.HTTPError as e:
            raise HTTPException(status_code=500, detail=f"Error communicating with the API: {str(e)}")

async def set_external_ip(forwarded_host):
    try:
        ip, port = forwarded_host.split(":")
        ip_obj = ipaddress.IPv4Address(ip)
        if port != os.environ.get("VAST_TCP_PORT_1111"):
            return
        async with httpx.AsyncClient() as client:
            response = await client.put(f"{tunnel_manager}/set-public-ip/{ip}")
    except Exception:
        return

    return

def parse_ansi(line):
    ansi_colors = {
        '30': 'black', '31': 'red', '32': 'green', '33': 'yellow',
        '34': 'blue', '35': 'magenta', '36': 'cyan', '37': 'white',
        '90': 'gray', '91': 'lightred', '92': 'lightgreen', '93': 'lightyellow',
        '94': 'lightblue', '95': 'lightmagenta', '96': 'lightcyan', '97': 'white'
    }
    
    def replace_color(match):
        code = match.group(1)
        if code in ansi_colors:
            return f'<span style="color: {ansi_colors[code]};">'
        elif code == '0':
            return '</span>'
        return ''
    
    return re.sub(r'\033\[(\d+)m', replace_color, line)

def highlight_log_level(line):
    if 'WARN' in line.upper():
        return f'<span class="warning">{line}</span>'
    elif 'ERR' in line.upper():
        return f'<span class="error">{line}</span>'
    return f'<span>{line}</span>'

async def get_log_files():
    """Retrieve all log files in the directory."""
    return {f for f in os.listdir(tail_directory) if f.endswith('.log')}

async def read_file_lines(filepath, queues, buffer):
    """Read existing lines in a file, then switch to tailing mode to add new lines."""
    try:
        async with aiofiles.open(filepath, mode="r") as f:
            # Step 1: Read any existing lines in the file initially
            async for line in f:
                if line:
                    message = line.strip()
                    buffer.append(message)
                    if len(buffer) > MAX_LINES:
                        buffer.popleft()

                # Broadcast the line to all clients in parallel
                await asyncio.gather(*(queue.put(message) for queue in queues.values()))
            
            # Step 2: Switch to "tailing" mode
            previous_size = os.path.getsize(filepath)
            while True:
                current_size = os.path.getsize(filepath)
                
                # Check for file rotation or truncation
                if current_size < previous_size:
                    await f.seek(0)
                    previous_size = current_size

                line = await f.readline()
                if line:
                    message = line.strip()
                    buffer.append(message)
                    if len(buffer) > MAX_LINES:
                        buffer.popleft()
                    
                    await asyncio.gather(*(queue.put(message) for queue in queues.values()))
                else:
                    await asyncio.sleep(1)

    except (FileNotFoundError, PermissionError) as e:
        print(f"Error opening file: {e}")
    except (OSError, IOError) as e:
        print(f"File read error: {e}")


async def monitor_log_files():
    """Monitors all log files and broadcasts new lines to all client queues."""
    try:
        while True:
            log_files = await get_log_files()
            
            # Start a reader task for each new log file
            for log_file in log_files:
                file_path = os.path.join(tail_directory, log_file)
                if log_file not in log_tasks:
                    log_buffers[log_file] = deque(maxlen=MAX_LINES)
                    task = asyncio.create_task(read_file_lines(file_path, client_queues, log_buffers[log_file]))
                    log_tasks[log_file] = task

            # Clean up tasks for deleted log files
            for log_file in list(log_tasks):
                if log_file not in log_files:
                    log_tasks[log_file].cancel()
                    del log_tasks[log_file]
                    if log_buffers[log_file]:
                        del log_buffers[log_file]

            await asyncio.sleep(5)  # Check for new/removed files every 5 seconds
    except asyncio.CancelledError:
        # Graceful shutdown cleanup
        print("Monitor log files task cancelled.")

async def stream_logs(request: Request):
    """Stream logs to the client from a dedicated queue, including recent log history."""
    queue = asyncio.Queue()
    client_id = id(queue)
    client_queues[client_id] = queue

    # First, send the last 500 lines from each log buffer
    for log_file, buffer in log_buffers.items():
        for line in buffer:
            await queue.put(line)

    try:
        while True:
            # Exit if the client disconnects
            if await request.is_disconnected():
                return
            
            # Get the next line in the queue
            line = await queue.get()
            queue.task_done()  # Mark task as done
            
            if line is None:
                return  # Graceful shutdown

            # Process and stream the log line to the client
            html_content = highlight_log_level(parse_ansi(line))
            yield f"data: {html_content}\n\n"
    finally:
        # Clean up the client's queue upon disconnect
        client_queues.pop(client_id, None)

@app.get("/stream-logs")
async def get_stream_logs(request: Request):
    return StreamingResponse(stream_logs(request), media_type="text/event-stream")

@app.get("/download-logs")
async def download_logs(filename: str = None):
    """
    Zip the /var/log directory and serve it as a downloadable file.
    
    Parameters:
    - filename: Optional custom filename for the zip file
    """
    try:
        # Create a memory buffer to store the zip file
        zip_buffer = io.BytesIO()
        
        # Define the directory to zip
        log_dir = "/var/log"
        
        # Check if the directory exists
        if not os.path.exists(log_dir):
            raise HTTPException(status_code=404, detail="Log directory not found")
        
        # Use provided filename or generate one with timestamp
        if not filename:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            zip_filename = f"logs_{timestamp}.zip"
        else:
            # Ensure the filename ends with .zip
            zip_filename = filename if filename.endswith('.zip') else f"{filename}.zip"
        
        # Create a zip file in the memory buffer
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zipf:
            # Walk through the directory and add all files to the zip
            for root, dirs, files in os.walk(log_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    # Calculate the relative path for the file inside the zip
                    relative_path = os.path.relpath(file_path, os.path.dirname(log_dir))
                    try:
                        zipf.write(file_path, relative_path)
                    except (PermissionError, zipfile.LargeZipFile, OSError) as e:
                        # Skip files that can't be accessed or are too large
                        continue
        
        # Reset the buffer position to the beginning
        zip_buffer.seek(0)
        
        # Return the zip file as a downloadable response
        return StreamingResponse(
            zip_buffer,
            media_type="application/zip",
            headers={"Content-Disposition": f"attachment; filename={zip_filename}"}
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error creating zip file: {str(e)}")

@app.get("/system-metrics")
async def get_system_metrics():
    # Try to get container memory metrics first
    container_memory = get_container_memory_stats()
    
    # Initialize metrics dictionary with memory info
    metrics = {
        'ram': container_memory if container_memory else {
            'total': psutil.virtual_memory().total,
            'used': psutil.virtual_memory().used,
            'percent': psutil.virtual_memory().percent
        },
        'disk': {
            'total': psutil.disk_usage('/').total,
            'used': psutil.disk_usage('/').used,
            'percent': psutil.disk_usage('/').percent
        }
    }
    
    # Add container detection info
    metrics['environment'] = 'container' if is_in_container() else 'host'
    
    # Get GPU metrics from both NVIDIA and AMD sources
    all_gpus = []
    nvidia_error = None
    rocm_error = None
    
    # Try to get NVIDIA GPUs
    try:
        nvidia_gpus = GPUtil.getGPUs()
        all_gpus.extend(nvidia_gpus)
    except Exception as e:
        nvidia_error = str(e)
    
    # Try to get ROCm GPUs
    try:
        rocm_gpus = get_rocm_gpus()
        all_gpus.extend(rocm_gpus)
    except Exception as e:
        rocm_error = str(e)
        
    # Calculate metrics if any GPUs are found
    if all_gpus:
        # Calculate average load across all GPUs
        avg_load = np.mean([gpu.load for gpu in all_gpus])
        
        # Sum total and used memory across all GPUs
        # Handle potential unit differences between NVIDIA and ROCm
        total_memory = 0
        used_memory = 0
        
        for gpu in all_gpus:
            # For ROCm GPUs, memoryTotal might be in bytes, while NVIDIA is in MB
            if hasattr(gpu, 'memoryTotal_mb'):
                # Use the MB values directly if available
                total_memory += gpu.memoryTotal_mb
                used_memory += gpu.memoryUsed_mb
            else:
                # Assume standard GPUtil format which is already in MB
                total_memory += gpu.memoryTotal
                used_memory += gpu.memoryUsed
        
        # Calculate overall memory usage percentage
        memory_percent = (used_memory / total_memory * 100) if total_memory > 0 else 0
        
        metrics['gpu'] = {
            'count': len(all_gpus),
            'avg_load_percent': float(avg_load * 100),  # Convert to percentage
            'memory_used': float(used_memory),
            'memory_total': float(total_memory),
            'memory_percent': float(memory_percent),
            'memory_unit': 'MB'  # Add unit for clarity
        }
        
        # Add GPU details by type
        nvidia_count = len([gpu for gpu in all_gpus if hasattr(gpu, 'id') and not isinstance(gpu.id, str)])
        rocm_count = len(all_gpus) - nvidia_count
        
        if nvidia_count > 0:
            metrics['gpu']['nvidia_count'] = nvidia_count
        if rocm_count > 0:
            metrics['gpu']['amd_count'] = rocm_count
            
    else:
        metrics['gpu'] = {
            'count': 0,
            'avg_load_percent': 0,
            'memory_used': 0,
            'memory_total': 0,
            'memory_percent': 0,
            'memory_unit': 'MB'  # Keep consistent unit notation
        }
        
        # Add error information if applicable
        errors = {}
        if nvidia_error:
            errors['nvidia'] = nvidia_error
        if rocm_error:
            errors['rocm'] = rocm_error
            
        if errors:
            metrics['gpu']['errors'] = errors

    return JSONResponse(content=metrics)

# Register shutdown event handler
@app.on_event("shutdown")
async def on_shutdown():
    for client_id, queue in client_queues.items():
        await queue.put(None)  # Send `None` to each queue to signal disconnection

    for task in log_tasks.values():
        task.cancel()

    log_monitor.cancel()

    await asyncio.sleep(1)

@app.on_event("startup")
async def startup_event():
    global log_monitor
    log_monitor = asyncio.create_task(monitor_log_files())




