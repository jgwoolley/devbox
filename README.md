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

Builds the image (if needed), starts the container, and prints the URL and a generated password.

```console
$ ./up.sh
--------------------------------------------------------
Container 'claude-browser-ubuntu' is already running.
URL:      http://localhost:8080
Password: XXXXXXXXXXXXXXXX
--------------------------------------------------------
```

Open the URL in your browser and sign in with the password.

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
URL:      http://localhost:8080
Password: XXXXXXXXXXXXXXXX
--------------------------------------------------------
```

### Tear down: [`./down.sh`](./down.sh)

> [!WARNING]
> This deletes **everything**: the container, the image, and the `claude_coder_home` volume, including your workspace files and Claude Code history. Push or copy anything you want to keep first.

```console
$ ./down.sh
claude-browser-ubuntu
claude-browser-ubuntu
claude_coder_home
Untagged: claude-vscode-ubuntu:latest
Deleted: sha256:78586e41...
```
