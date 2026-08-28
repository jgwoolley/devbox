#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="claude-vscode-ubuntu"
CONTAINER_NAME="claude-browser-ubuntu"
PORT="8080"
VOLUME_NAME="claude_coder_home"

FORCE_REBUILD=false

# Parse command line flags properly
while [[ $# -gt 0 ]]; do
  case $1 in
    --rebuild|-r)
      FORCE_REBUILD=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

get_container_password() {
  docker inspect "${CONTAINER_NAME}" | jq -r '.[0].Config.Env[] | select(startswith("PASSWORD=")) | split("=")[1]' 2>/dev/null || true
}

cleanup_container() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping and removing existing container '${CONTAINER_NAME}'..."
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}

if [ "$FORCE_REBUILD" = true ]; then
  echo "Force rebuild flag detected."
  cleanup_container
  echo "Building Docker image '${IMAGE_NAME}'..."
  docker build -t "${IMAGE_NAME}" .
fi

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "Image '${IMAGE_NAME}' does not exist. Building image..."
  docker build -t "${IMAGE_NAME}" .
fi

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  ACTIVE_PASS=$(get_container_password)
  echo "--------------------------------------------------------"
  echo "Container '${CONTAINER_NAME}' is already running."
  echo "URL:      http://localhost:${PORT}"
  echo "Password: ${ACTIVE_PASS}"
  echo "--------------------------------------------------------"
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container '${CONTAINER_NAME}' exists but is stopped. Starting it..."
  docker start "${CONTAINER_NAME}" >/dev/null
  ACTIVE_PASS=$(get_container_password)
  echo "--------------------------------------------------------"
  echo "Container started successfully!"
  echo "URL:      http://localhost:${PORT}"
  echo "Password: ${ACTIVE_PASS}"
  echo "--------------------------------------------------------"
  exit 0
fi

PASSWORD="${PASSWORD:-$(openssl rand -base64 12)}"

# Ensure local host directory exists before mounting
mkdir -p "${HOME}/Projects"

echo "Starting new container '${CONTAINER_NAME}'..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${PORT}:8080" \
  -e PASSWORD="${PASSWORD}" \
  -v "${VOLUME_NAME}:/home/ubuntu" \
  -v "${HOME}/Projects:/home/ubuntu/workspace" \
  "${IMAGE_NAME}" >/dev/null

echo "--------------------------------------------------------"
echo "Setup complete!"
echo "URL:      http://localhost:${PORT}"
echo "Password: ${PASSWORD}"
echo "--------------------------------------------------------"