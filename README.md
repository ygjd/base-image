# Vast.ai Base Docker Image

## About

This repository contains the Dockerfile and associated configuration files for building a base Docker image suitable for use at [Vast.ai](https://vast.ai)

You can find pre-built versions at DockerHub vastai/base_image suitable for extending, or you can build from scratch after cloning the repository.

Pre-built images generally extend [nvidia/cuda:[CUDA_VERSION]-cudnn-devel-ubuntu[UBUNTU_VERSION]](https://hub.docker.com/r/nvidia/cuda/tags) or [rocm/dev-ubuntu-22.04](https://hub.docker.com/r/rocm/dev-ubuntu-22.04/tags).  These are large images, but due to host machine image caching, these will be fast to start where the base layers already exist.

## Features

- Runs in Jupyter, SSH and Args launch modes
- CUDA, OpenCL & ROCm supported
- Pre-installs the [Vast CLI](https://pypi.org/project/vastai/) tool for easy instance management from inside the container.
- Provides TLS, secure tunnels & authentication mechanism for web apps via the [Instance Portal](#instance-portal).
- Application management via [supervisor](https://supervisord.readthedocs.io/en/latest/).
- Stores the main Python virtual environment in `$DATA_DIRECTORY` (generally `/workspace`)
- Optionally 'Hydrates' the data directory on first boot moving all files to the top overlayfs layer making the entire directory and virtual environment portable between instances.
- Adds and starts additional useful applications to simplify working with remote instances.
- Adds a non-root user `user` to simplify launching applications which refuse to run as root.
- Supports remote configuration via the `PROVISIONING_SCRIPT` environment variable.

## Instance Portal

This is a simple web application which uses [Caddy](https://caddyserver.com/) as a reverse proxy to add TLS and authentication support to the applications it is serving. For TLS to work without certificate warnings, users should install the 'Jupyter' certificate as detailed in the [instance setup](https://vast.ai/docs/instance-setup/jupyter#installing-the-tls-certificate) documentation.

Web applications should be launched with their configuration set to listen only on `localhost`. The external port (`-p port:port`) should not be used here as Caddy will bind to that port and serve the application using the TLS certificate and key located at `/etc/instance.crt` and `/etc/instance.key`.

To access the running applications you should click the 'Open' button from the instance card.  

![Open Button](docs/images/instance-card-open-button.png)

This will pass a token (value of environment variable `OPEN_BUTTON_TOKEN`) to Caddy, causing a cookie to be set allowing access.  If the cookie or token are not present then a basic authentication login dialog will be displayed. Login username is `vastai` and the password is the value of environment variable `OPEN_BUTTON_TOKEN`.

On successful login you should see a screen similar to this:

![Instance Portal landing page](docs/images/instance-portal-application-list.png)

The IP address links will lead to the open ports shown in the leftmost column.  Instance portal itself is automatically started with a Cloudflare tunnel allocated - These are particularly useful if you need to connect to an instance in the event the direct link is unavailable or if you'd like to share a temporary link to a running application without sharing the instance IP address.

You can start, stop and refresh tunnel links using the buttons to the right.


### Tunnels Tab

![Instance Portal tunnels tab](docs/images/instance-portal-tunnels.png)

This tab will show a list of existing `cloudflared` tunnels linked to the applications running in the Applications tab.  You can also use the input box at the bottom to create a new 'quick' tunnel linking to any local port on the instance.  This is useful when you want to test an application but haven't started the instance with the required open ports.

To integrate a named tunnel with domain mapping or virtual local networking you can set environment variable `CF_TUNNEL_TOKEN`. Instance portal will then provide domain links to your running services where the port has been configured.  See the [Cloudlfare documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) for further information.


### Instance Logs Tab

![Instance Portal logs tab](docs/images/instance-portal-logs.png)

The logs tab displays a live stream of information pulled from all `*.log` files contained in the `/var/log/portal/` directory.  Application startup scripts generally pipe the output to `tee -a /var/log/portal/${PROC_NAME}.log` so that the information is available both inside the instance and via the Vast GUI logging button.

## Configuration

On the first start of an instance, the Instance Portal configuration file `/etc/portal.yaml` will be written using information obtained from the environment variable `PORTAL_CONFIG`.

The default is:

```
PORTAL_CONFIG="localhost:1111:11111:/:Instance Portal|localhost:8080:8080:/:Jupyter|localhost:8384:18384:/:Syncthing"
```

Which translates to:

```
applications:
  Instance Portal:
    hostname: localhost
    external_port: 1111
    internal_port: 11111
    open_path: /
    name: Instance Portal
  Jupyter:
    hostname: localhost
    external_port: 8080
    internal_port: 8080 # Internal port = External Port: No proxying, only links
    open_path: /
    name: Jupyter
  Syncthing:
    hostname: localhost
    external_port: 8384
    internal_port: 18384
    open_path: /
    name: Syncthing
```

The config file is used by both Caddy and the Instance Portal landing page to serve the application and to generate the correct links respectively.

You can edit the config file at any time, but adding applications will require Caddy to be restarted.  Simply issue the command `supervisorctl restart caddy` from a terminal.  The external ports must also be available.


## Applications & Startup

The entrypoint for this image and all derivatives is `/opt/instance-tools/bin/entrypoint.sh`

We run a fairly straightforward script to set up the instance.  The process briefly consists of the following steps:

- Check whether the user wants Supervisor to manage Jupyter and modify the config to support it.
- Store all environment variables in `/etc/environment` so they will be available to login shells.
- Create a lock file at `/.provisioning` to be used in Supervisor startup scripts to determine whether it is safe to launch
- Copy root user SSH keys to the user account to enable non-root login.
- Touch all files in `$DATA_DIRECTORY` to promote them to the top overlayfs layer (background process).
- Generates TLS certificate if not already present.
- Launches Supervisor process in the background
- Download and execute remote file if defined in `PROVISIONING_SCRIPT` variable
- Remove the `/.provisioning` lock file.
- Wait indefinitely, only exiting if Supervisor is stopped.


### Supervisor

Supervisor is used as the application orchestrator in the absence of systemd in unprivileged docker containers.  Configuration files are stored in `/etc/supervisor/conf.d/` and startup scripts are found in `/opt/supervisor-scripts/`

While Supervisor is capable of starting applications directly, we use a wrapper script for process launching.  This allows for greater control in the startup routine.  specifically, we can check for the presence of application names in the `/etc/portal.yaml` file - If the user has removed the configuration, we can assume that they do not want to start that particular application.

Some useful Supervisor commands:

```
# View all processes
supervisorctl status

# Control specific services
supervisorctl start jupyter
supervisorctl stop syncthing
supervisorctl restart caddy

# Reload configuration after changes
supervisorctl reload

# Read recent logs
supervisorctl tail jupyter
supervisorctl tail -f syncthing  # Follow mode
```

Full documentation for Supervisor can ve viewed at https://supervisord.readthedocs.io/en/latest

### Jupyter

Jupyter will only start via Instance Portal if the template is launched in SSH or Args modes.  This is mainly included for debugging other launch modes or where you need to configure Jupyter's startup options.

To enable this, the internal port in `PORTAL_CONFIG` will need to be set to `18080` - This is handled automatically by the entrypoint script but mentioned here for clarity.

When the template type is Jupyter, management of the Jupyter process will be left to the launch script at `/.launch` and this process will exit.

You may wish to build this image with alternative configuration options - These can be achieved by editing the file `ROOT/opt/supervisor-scripts/jupyter.sh`

### Syncthing

Syncthing is a peer-to-peer file synchronization service.  It allows for keeping files in sync across a range of machines which may include your local PC and one or more cloud instances.  For usage instructions see the project's [documentation](https://docs.syncthing.net/).

### Cron

Cron is enabled in all launch modes.  Simply add entries to your crontab if you need job scheduling.

### NVM

Node version manager is installed to assist with running node applications.  The latest LTS version of node is installed during the image build.

## Building the Image

This image can be built on CPU-only systems.  A GPU is only required at runtime, not for building.

Building is very straightforward.  Simply clone the repository, `cd vast-base` and then issue the build command.

```
docker buildx build .
```

You can configure the base image for this image by passing a `BASE_IMAGE` build argument.

Naturally, you can use this image as a base for building your own Docker image with additional features.  Simply start your Dockerfile with 

```
FROM vastai/vast-base:<TAG>
```

Then install your required software into the `${DATA_DIRECTORY}venv/main` venv.  All you will need to do next is supply the Supervisor config files and an appropriate wrapper scripts to launch any additional services.  See the existing launchers for Jupyter and Syncthing for guidance and inspiration.

## Dynamic Templates

While it's usually best to build all required software into the Docker image, sometimes it may not be possible - Or you might just want to put together a quick proof-of-concept template. For this, remotely host a shell script (GitHub, Gist etc.) and set the raw (plaintext) URL in the `PROVISIONING_SCRIPT` environment variable.  

In the script you'll want to activate the main virtual environment:

```
. ${DATA_DIRECTORY}venv/main/bin/activate
```

Then simply install any required software packages and echo/download the required Supervisor config and startup scripts.

Finally, issue the reload instruction to Supervisor:

```
supervisorctl reload
```

## Template Links

These templates exist to demonstrate the default configuration.  They may be useful as a starting point 

[Jupyter Launch Mode](https://cloud.vast.ai/?ref_id=62897&creator_id=62897&name=Vast%20Base%20Image)

[SSH Launch Mode](https://cloud.vast.ai/?ref_id=62897&creator_id=62897&name=Vast%20Base%20Image%20-%20SSH)

[Args Launch Mode](https://cloud.vast.ai/?ref_id=62897&creator_id=62897&name=Vast%20Base%20Image%20-%20ARGS)
