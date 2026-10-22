#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CONTAINER_NAME="claude-browser-ubuntu"
PORT="${HTTP_PORT:-8080}"
HOST="${DEVBOX_HOST:-code.localhost}"
VOLUME_NAME="claude_coder_home"
DOCKER_SOCK="/var/run/docker.sock"

FORCE_REBUILD=false

usage() {
  cat <<USAGE
Usage: ./up.sh [OPTIONS]

Build (if needed) and start the code-server container via Docker Compose,
then print its URL and password.

Options:
  -r, --rebuild   Rebuild the image from scratch and recreate the container
  -h, --help      Show this help and exit

Environment:
  PASSWORD        Password for a new container (default: randomly generated)
  HTTP_PORT       Host port for Traefik (default: 8080)
  DEVBOX_HOST     Hostname routed to code-server (default: code.localhost)
  DOCKER_GID      Group ID of the host Docker socket (default: auto-detected)

Container: ${CONTAINER_NAME}   Routed by Traefik: http://${HOST}:${PORT}
Volume:    ${VOLUME_NAME} -> /home/ubuntu
Workspace: \${HOME}/Projects -> /home/ubuntu/workspace
Docker:    ${DOCKER_SOCK} is mounted into the container
USAGE
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --rebuild|-r)
      FORCE_REBUILD=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Reuse the password of an existing container so a restart doesn't change it
existing_password() {
  docker inspect "${CONTAINER_NAME}" 2>/dev/null \
    | jq -r '.[0].Config.Env[] | select(startswith("PASSWORD=")) | split("=")[1]' 2>/dev/null || true
}

if [[ -z "${PASSWORD:-}" ]]; then
  PASSWORD="$(existing_password)"
  PASSWORD="${PASSWORD:-$(openssl rand -base64 12)}"
fi
export PASSWORD

# The container's ubuntu user needs the socket's group to talk to the host daemon
if [[ -z "${DOCKER_GID:-}" ]]; then
  DOCKER_GID="$(stat -c %g "${DOCKER_SOCK}" 2>/dev/null || stat -f %g "${DOCKER_SOCK}" 2>/dev/null || echo 999)"
fi
export DOCKER_GID

# Ensure local host directory exists before mounting
mkdir -p "${HOME}/Projects"

if [ "$FORCE_REBUILD" = true ]; then
  echo "Force rebuild flag detected."
  docker compose build --no-cache
  docker compose up -d --force-recreate
else
  docker compose up -d --build
fi

echo "--------------------------------------------------------"
echo "Container '${CONTAINER_NAME}' is up."
echo "URL:      http://${HOST}:${PORT}"
echo "Password: ${PASSWORD}"
echo "--------------------------------------------------------"
