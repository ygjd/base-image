from fastapi import FastAPI, Request, HTTPException
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from collections import deque
import yaml
import httpx
import asyncio
import aiofiles
import signal
import os
import re
import time
import ipaddress

tunnel_manager=os.environ.get("TUNNEL_MANAGER", "http://localhost:11112")
if os.environ.get("ENABLE_HTTPS", "true").lower() != "false":
    proxy_address = "https://localhost"
else:
    proxy_address = "http://localhost"


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

def load_config():
    yaml_path = '/etc/portal.yaml'
    
    # Wait until the file exists - caddy-manager handles config writing
    while not os.path.exists(yaml_path):
        print(f"Waiting for {yaml_path} to appear...")
        time.sleep(1)

    with open(yaml_path, 'r') as file:
        return yaml.safe_load(file)['applications']

def strip_port(host):
    return host.split(':')[0]

templates.env.filters["strip_port"] = strip_port

tunnels = {}
tunnel_api_timeout=httpx.Timeout(connect=5.0, read=30.0, write=5.0, pool=5.0)

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    await set_external_ip(request.headers.get("X-Forwarded-Host"))
    config = load_config()
    return templates.TemplateResponse("index.html", {
        "request": request,
        "applications": config,
        "proxy_address": proxy_address,
        "tunnels": tunnels,
        "auth_token": request.cookies.get(f"" + os.environ.get('VAST_CONTAINERLABEL') + "_auth_token")
        })


@app.get("/get-direct-url/{port}")
async def get_direct_url(port: int):
    url = f"{tunnel_manager}/get-direct-url/{port}"
    async with httpx.AsyncClient(timeout=tunnel_api_timeout) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            result = response.json()
            return HTMLResponse(result['result'])
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




