#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="claude-vscode-ubuntu"
CONTAINER_NAME="claude-browser-ubuntu"
PORT="8080"
VOLUME_NAME="claude_coder_home"

FORCE_REBUILD=false

# Parse command line flags
for arg in "$@"; do
  case $arg in
    --rebuild|-r)
      FORCE_REBUILD=true
      shift
      ;;
    *)
      ;;
  esac
done

# Function to fetch the PASSWORD environment variable using jq
get_container_password() {
  docker inspect "${CONTAINER_NAME}" | jq -r '.[0].Config.Env[] | select(startswith("PASSWORD=")) | split("=")[1]' 2>/dev/null || true
}

# Function to stop and remove container
cleanup_container() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping and removing existing container '${CONTAINER_NAME}'..."
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}

# Handle Force Rebuild Flag
if [ "$FORCE_REBUILD" = true ]; then
  echo "Force rebuild flag detected."
  cleanup_container
  echo "Building Docker image '${IMAGE_NAME}'..."
  docker build -t "${IMAGE_NAME}" .
fi

# Build image if it doesn't exist yet
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "Image '${IMAGE_NAME}' does not exist. Building image..."
  docker build -t "${IMAGE_NAME}" .
fi

# Check if container is already running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  ACTIVE_PASS=$(get_container_password)
  echo "--------------------------------------------------------"
  echo "Container '${CONTAINER_NAME}' is already running."
  echo "URL:      http://localhost:${PORT}"
  echo "Password: ${ACTIVE_PASS}"
  echo "--------------------------------------------------------"
  exit 0
fi

# Check if container exists but is stopped
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

# Generate a random password if not supplied in environment
PASSWORD="${PASSWORD:-$(openssl rand -base64 12)}"

# Run a fresh container
echo "Starting new container '${CONTAINER_NAME}'..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --user "$(id -u):$(id -g)" \
  -p "${PORT}:8080" \
  -e PASSWORD="${PASSWORD}" \
  -v "${VOLUME_NAME}:/home/coder" \
  -v "${HOME}/Projects:/home/coder/workspace" \
  "${IMAGE_NAME}" >/dev/null

echo "--------------------------------------------------------"
echo "Setup complete!"
echo "URL:      http://localhost:${PORT}"
echo "Password: ${PASSWORD}"
echo "--------------------------------------------------------"