
# Stable Diffusion Fooocus

> > Focus on prompting and generating.


## Contents

1. [About Fooocus](#about-fooocus)
2. [Connecting to the Instance](#connecting-to-the-instance)
3. [Additional Software](#additional-software)
4. [Application Management](#application-management)
5. [Dynamic Provisioning](#dynamic-provisioning)
6. [Useful Links](#useful-links)

## About Fooocus

This Stable Diffusion Fooocus image is built and maintained by Vast.ai. It contains development libraries to enable building custom extensions and add-ons. Please see the associated documentation below for configuration details.

The installation directory is `/workspace/Fooocus`, where you can download models and extensions.

No models are included in the Docker image, but Fooocus will determine the correct models to download depending on the startup parameters defined in `FOOOCUS_ARGS`.

### Upgrading Fooocus

Fooocus can be upgraded by checking out a new version with git, installing the requirements and then restarting:

```bash
cd /workspace/Fooocus
git checkout main
git fetch
git checkout [desired_ref]
pip install -r requirements_versions.txt
supervisorctl restart fooocus
```

### Transferring to a New Instance

The `/workspace/` directory contains all of Fooocus's code, models, extensions, and dependencies. To migrate to a different instance, simply copy this directory from one instance to another and then reboot. Everything will be preserved.

You can find more information about copying data between instances [here](https://vast.ai/docs/data-management/data-movement).

## Connecting to the Instance

There are several methods you can use to interact with your instance.

### Jupyter Button

Press the Jupyter button to be immediately logged in to  Jupyter Lab or Notebook (Configure this in the template settings).  Here you can:
- Manage your files
- Run Jupyter notebooks
- Open a terminal session

### SSH

Press the SSH button to reveal the SSH connection details for your instance.  We only support key based SSH login so check out [this guide](https://docs.vast.ai/sshscp) for help setting this up.

SSH sessions will automatically launch inside tmux to keep the session active even if you disconnect.  You can disable this behavior by running the following command `touch ~/.no_auto_tmux` and then re-connecting.

If you prefer not to add SSH keys, you can use Jupyter based terminals instead.

### SSH Port Forwarding

Instead of connecting to ports exposed to the internet, you can use SSH port forwarding to securely access services on your instance. This method connects directly to the internal ports, bypassing the Caddy authentication layer.

#### Port Reference Table

| Service | External Port | Internal Port |
| --- | --- | --- |
| Instance Portal | 1111 | 11111 |
| Fooocus | 7865 | 17865 |
| Syncthing | 8384 | 18384 |
| Jupyter | 8080 | 8080 |

When creating SSH port forwards, use the internal ports listed above. These ports don't require authentication or TLS since they're only accessible through your SSH tunnel. See the [Instance Portal](#open-button-instance-portal) for more details on this security model.

* Note: Jupyter is not proxied so forwarding this will require connection to https://localhost:8080 and you will need to supply the auth token which is stored in the instance in environment variable `JUPYTER_TOKEN`. 

#### Example: Forwarding Fooocus to localhost

To forward Fooocus to your local machine:

```bash
ssh root@INSTANCE_IP -p SSH_PORT -L 7865:localhost:17865
```

This command:

- Creates a SSH local port forward for your localhost:7865
- Connects to the instance internal Fooocus port (17865)
- Allows you to access the application at http://localhost:7865 on your machine
- Maintains a secure, encrypted connection through SSH

The application will now be available on your local machine without requiring the authentication that would be needed when accessing the externally exposed port.


### Open Button (Instance Portal)

The Instance Portal is your gateway to managing web applications running on your instance. It uses [Caddy](https://caddyserver.com/) as a reverse proxy to provide secure TLS and authentication for all your applications.

#### Getting Started

1. **Set Up TLS**: To avoid certificate warnings, install the 'Jupyter' certificate by following our [instance setup guide](https://vast.ai/docs/instance-setup/jupyter#installing-the-tls-certificate).

2. **Access Your Applications**: Simply click the 'Open' button on your instance card:

![Open Button](https://raw.githubusercontent.com/vast-ai/base-image/refs/heads/main/docs/images/instance-card-open-button.png)

This sets a cookie using your `OPEN_BUTTON_TOKEN`, granting you access. Without this, you'll see a login prompt (username: `vastai`, password: your `OPEN_BUTTON_TOKEN`).

#### Programmatic Access

For automated or API access, you can authenticate to any application by including a Bearer token in your HTTP requests:

```bash
Authorization: Bearer <OPEN_BUTTON_TOKEN>
```

This is particularly useful for scripts, automated tools, or when you need to access your applications programmatically without browser interaction.
Once logged in, you'll see your application dashboard:

![Instance Portal landing page](https://raw.githubusercontent.com/vast-ai/base-image/refs/heads/main/docs/images/instance-portal-application-list.png)

The dashboard shows all available ports and their corresponding applications. The Instance Portal can create Cloudflare tunnels - perfect for sharing temporary application links or accessing your instance when direct connections aren't available.

Start, stop, and refresh tunnel links using the dashboard controls.

#### Managing Tunnels

![Instance Portal tunnels tab](https://raw.githubusercontent.com/vast-ai/base-image/refs/heads/main/docs/images/instance-portal-tunnels.png)

The Tunnels tab displays your active Cloudflare tunnels. You can:
- View existing tunnels linked to running applications
- Create new 'quick tunnels' to any local port
- Test applications without opening ports on your instance

Want to use custom domains or virtual networks? Set the `CF_TUNNEL_TOKEN` environment variable to enable domain mapping. Check out the [Cloudflare documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) for details.

#### Monitoring Your Instance

![Instance Portal logs tab](https://raw.githubusercontent.com/vast-ai/base-image/refs/heads/main/docs/images/instance-portal-logs.png)

The Logs tab provides live streaming of all `*.log` files from `/var/log/portal/`. Outputs for the included applications are piped to `tee -a /var/log/portal/${PROC_NAME}.log`, making them accessible both within your instance and through the Vast GUI logging button.

#### Configuration

The Instance Portal configuration lives in `/etc/portal.yaml`, generated on first start using your `PORTAL_CONFIG` environment variable.

Need to modify the configuration in a running instance? Edit `/etc/portal.yaml` anytime, then restart Caddy with `supervisorctl restart caddy`. Remember that any new applications will need their external ports to be available for direct access.

## Additional Software

Jupyter is always started when run with the Jupyter launch mode.  All other software is managed by supervisord. 

Manage application startup by modifying the `PORTAL_CONFIG` environment variable before instance start, or by editing the file `/etc/portal.yaml` in a running instance.

To disable all additional web app features, simply remove environment variables `PORTAL_CONFIG` and `OPEN_BUTTON_PORT`

### Syncthing

A powerful file synchronization tool that keeps your development environment in sync across devices. Ideal for maintaining consistent workspaces across multiple instances or syncing datasets. Features:
- Peer-to-peer file synchronization
- Real-time file updates
- Conflict resolution
- Selective sync options

See the [Syncthing documentation](https://docs.syncthing.net/) for setup instructions.

### Tensorboard

Visualization toolkit for machine learning experiments, helping you track metrics, view model graphs, and analyze training results. Our configuration:
- By default, monitors `${DATA_DIRECTORY}` (`/workspace`)
- Customize log directory via `TENSORBOARD_LOG_DIR` environment variable
- Automatically detects and displays new experiments

### Cron

The reliable Linux task scheduler, perfect for automating routine tasks in your instance:
- Schedule model training jobs
- Automate data downloads
- Run periodic maintenance tasks
- Enabled in all launch modes
Just add entries to your crontab to get started.

### Vast.ai Instance Control

The Vast.ai CLI tool comes pre-installed on your instance, allowing you to stop it from within. An instance-specific API key is already configured, giving you the ability to control this instance while you're logged in.

To stop the instance from inside itself, run:

```bash
vastai stop instance $CONTAINER_ID
```

You can incorporate this command into scripts that run on the instance itself - for example, to shut down based on specific conditions. Combined with cron, you can automate when your instance stops based on your needs.

### NVM (Node Version Manager)

Manages Node.js environments, essential for many modern AI tools and visualization frameworks:
- Pre-installed with latest LTS Node.js version
- Supports popular ML visualization tools like TensorBoard.js
- Enables local development of model visualization dashboards
- Compatible with various AI/ML web interfaces and tools

### Application Management

We use Supervisor to orchestrate applications in the container. Configuration files live in `/etc/supervisor/conf.d/`, with startup scripts in `/opt/supervisor-scripts/`.

Rather than directly launcheing applications, we use wrapper scripts for better control. This allows us to check for application entries in `/etc/portal.yaml` - if an application isn't configured here, we assume you don't want to run it.

With cron as the notable exception, the supervisor startup scripts will refuse to start services unless the environment variable `OPEN_BUTTON_PORT=1111` has been set.  This allows you to use the base image with no additional extras.

Common Supervisor commands:
```bash
# View all processes
supervisorctl status

# Control specific services
supervisorctl start fooocus
supervisorctl stop syncthing
supervisorctl restart fooocus

# Reload configuration after changes
supervisorctl reload

# Read recent logs
supervisorctl tail caddy
supervisorctl tail -f syncthing  # Follow mode
```

Need more details? Check out the [Supervisor documentation](https://supervisord.readthedocs.io/en/latest).

## Dynamic Provisioning

Sometimes you need flexibility without rebuilding the entire image. For quick customizations:

Host a shell script remotely (GitHub, Gist, etc.)
Set the raw URL in `PROVISIONING_SCRIPT`

Here's a typical provisioning script:

```bash
#!/bin/bash
set -e

# Activate the main virtual environment
. ${DATA_DIRECTORY}venv/main/bin/activate

# Install your packages
pip install your-packages

# Download some useful files
wget -P "${DATA_DIRECTORY}" https://example.org/my-application.tar.gz
tar xvf "${DATA_DIRECTORY}/my-application.tar.gz"

# Set up any additional services
echo "my-supervisor-config" > /etc/supervisor/conf.d/my-application.conf
echo "my-supervisor-wrapper" > /opt/supervisor-scripts/my-application.sh
chmod +x /opt/supervisor-scripts/my-application.sh

# Reconfigure the instance portal
rm -f /etc/portal.yaml
PORTAL_CONFIG="localhost:1111:11111:/:Instance Portal|localhost:1234:11234:/:My Application"

# Reload Supervisor
supervisorctl reload
```

## Useful Links

- [Fooocus](https://github.com/lllyasviel/Fooocus)
- [Image Source](https://github.com/vast-ai/base-image/tree/main/derivatives/PyTorch/derivatives/fooocus)
- [Base Image](https://github.com/vast-ai/base-image)