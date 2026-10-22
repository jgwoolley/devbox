# devbox

A sandboxed development environment: [code-server](https://github.com/coder/code-server) (VS Code in the browser) running in a Docker container, preloaded with the tools I use.

## What's inside

Based on Ubuntu 24.04:

| Tool | Version |
| --- | --- |
| Node.js | 22 |
| Java (JDK) + Maven | 21 |
| .NET SDK | 10 |
| Python | 3 (system) |
| Build tools | `make`, `g++`, `git`, `curl`, `unzip` |
| Editor | code-server |
| AI | Claude Code (native installer, self-updating) |

Telemetry is disabled for .NET, code-server, and the bundled VS Code extensions.

Inside the container you run as the `ubuntu` user, with passwordless `sudo`. Your projects live in `/home/ubuntu/workspace`.

## Requirements

- Docker

## Usage

### Start: [`./up.sh`](./up.sh)

Builds the image (if needed), starts Traefik, Portainer and code-server, and prints the URLs and a generated password.

```console
$ ./up.sh
--------------------------------------------------------
Container 'claude-browser-ubuntu' is already running.
URL:      https://code.localhost  (trust certs/ca.crt once to remove the browser warning)
Traefik:  https://traefik.localhost  (user: admin, same password)
Portainer: https://portainer.localhost  (user: admin, same password)
Password: XXXXXXXXXXXXXXXX
--------------------------------------------------------
```

Open the URL and sign in with the password. The password is saved to `.env` as `CODER_PASSWORD` on first run and reused afterwards. It also protects the Traefik dashboard (basic auth) and is Portainer's admin password (min. 12 characters; Portainer rejects shorter ones).

### Services

| URL (defaults) | What | Login |
| --- | --- | --- |
| `https://code.localhost` | code-server (`DEVBOX_HOST`) | `CODER_PASSWORD` |
| `https://traefik.localhost` | Traefik dashboard (`TRAEFIK_HOST`) | `admin` / `CODER_PASSWORD` |
| `https://portainer.localhost` | Portainer CE (`PORTAINER_HOST`) | `admin` / `CODER_PASSWORD`, created on first start |

HTTP (port 80) redirects to HTTPS. Host ports are `HTTP_PORT` and `HTTPS_PORT`; every setting is documented in [`.env.example`](./.env.example). All services share the Docker network `devbox_network` (`NETWORK_NAME`).

Portainer takes its admin password only on its first start. If you start it once with another password, remove its volume (`docker compose rm -sf portainer && docker volume rm portainer_data`) and run `./up.sh` again.

### HTTPS certificate

`up.sh` creates a local CA (`certs/ca.crt`, 10 years) and a certificate signed by it for `localhost`, `*.localhost`, the three hostnames above and anything in `EXTRA_HOSTS`. The leaf certificate is reissued when a hostname is missing. Traefik serves it through `traefik/dynamic/tls.yml` (generated, git-ignored).

Browsers warn until they trust the CA, and **Firefox keeps its own store**, so import `certs/ca.crt` there (Settings → Privacy & Security → View Certificates → Authorities → Import, tick "Trust this CA to identify websites"). Copy the file to the machine your browser runs on if that is not this one. Chrome and the OS use the system store. Do not share `certs/ca.key`; anyone with it can mint certificates your browser trusts. If `certs/` is deleted, a new CA is created and must be imported again.

To rebuild the image from scratch (for example, after editing the `Dockerfile`), pass `--rebuild`:

```console
$ ./up.sh --rebuild
Force rebuild flag detected.
Stopping and removing existing container 'claude-browser-ubuntu'...
Building Docker image 'claude-vscode-ubuntu'...
[+] Building 0.5s (15/15) FINISHED
Starting new container 'claude-browser-ubuntu'...
--------------------------------------------------------
Setup complete!
URL:      https://code.localhost  (trust certs/ca.crt once to remove the browser warning)
Password: XXXXXXXXXXXXXXXX
--------------------------------------------------------
```

### Tear down: [`./down.sh`](./down.sh)

> [!WARNING]
> This deletes **everything**: the containers, the image, and the `claude_coder_home` and `portainer_data` volumes, including your workspace files and Claude Code history. Push or copy anything you want to keep first.

```console
$ ./down.sh
[+] Running 3/3
 ✔ Container claude-browser-ubuntu  Removed
 ✔ Volume claude_coder_home         Removed
 ✔ Volume portainer_data            Removed
 ✔ Image claude-vscode-ubuntu       Removed
```

## Adding a project

This stack owns the only Traefik. Other repos do not run their own: they join its network and add `traefik.*` labels
to the services that need a hostname. Start this stack first (`./up.sh`).

```yaml
networks:
  proxy:
    external: true
    name: devbox_network        # NETWORK_NAME here

services:
  web:
    networks: [default, proxy]  # backends such as a database stay on default only
    labels:
      - traefik.enable=true
      - traefik.docker.network=proxy
      - traefik.http.routers.myproj-web.rule=Host(`${WEB_HOST:-myproj.localhost}`)
      - traefik.http.routers.myproj-web.entrypoints=websecure
      - traefik.http.routers.myproj-web.tls=true
      - traefik.http.services.myproj-web.loadbalancer.server.port=8080
      # HTTPS-only backend with a self-signed cert:
      # - traefik.http.services.myproj-web.loadbalancer.server.scheme=https
      # - traefik.http.services.myproj-web.loadbalancer.serversTransport=insecure@file
```

- Prefix router and service names with the project name; they share one namespace across all projects.
- Keeping databases off `proxy` stops two projects' `postgres` hostnames from colliding.
- `*.localhost` names are covered by the certificate. For other names, set `EXTRA_HOSTS` and re-run `./up.sh`.
