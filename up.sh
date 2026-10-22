#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Resolve KEY from the environment, then .env, then the default (same defaults as compose.yml)
# and export it so Compose agrees with this script.
setting() {
  local key=$1 default=$2 value="${!1:-}"
  [[ -n $value ]] || value="$(grep -m1 "^${key}=" .env 2>/dev/null | cut -d= -f2- || true)"
  export "${key}=${value:-$default}"
}
setting CONTAINER_NAME claude-browser-ubuntu
setting VOLUME_NAME claude_coder_home
setting DOCKER_SOCK /var/run/docker.sock
setting HTTP_PORT 80
setting HTTPS_PORT 443
setting DEVBOX_HOST code.localhost
setting TRAEFIK_HOST traefik.localhost
setting PORTAINER_HOST portainer.localhost
setting EXTRA_HOSTS ""

# Omit the port from URLs when it is the HTTPS default
HTTPS_SUFFIX=""
[[ "${HTTPS_PORT}" == 443 ]] || HTTPS_SUFFIX=":${HTTPS_PORT}"

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
  CODER_PASSWORD  Password (default: CODER_PASSWORD= in .env, else generated and saved there)
  CONTAINER_NAME  Name of the code-server container (default: claude-browser-ubuntu)
  VOLUME_NAME     Volume mounted at /home/ubuntu (default: claude_coder_home)
  DOCKER_SOCK     Host Docker socket to mount (default: /var/run/docker.sock)
  HTTPS_PORT      Host HTTPS port for Traefik (default: 443)
  HTTP_PORT       Host HTTP port, redirects to HTTPS (default: 80)
  DEVBOX_HOST     Hostname routed to code-server (default: code.localhost)
  TRAEFIK_HOST    Hostname for the Traefik dashboard (default: traefik.localhost)
  EXTRA_HOSTS     Comma-separated extra hostnames for the certificate (*.localhost is always included)
  PORTAINER_HOST  Hostname for Portainer (default: portainer.localhost)
  DOCKER_GID      Group ID of the host Docker socket (default: auto-detected)

Container: ${CONTAINER_NAME}   Routed by Traefik: https://${DEVBOX_HOST}${HTTPS_SUFFIX}
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

# Password precedence: environment, then CODER_PASSWORD= in .env, then the existing container.
# A newly generated password is appended to .env (never rewriting it) so it persists.
if [[ -z "${CODER_PASSWORD:-}" ]]; then
  CODER_PASSWORD="$(grep -m1 '^CODER_PASSWORD=' .env 2>/dev/null | cut -d= -f2- || true)"
  if [[ -z "${CODER_PASSWORD}" ]]; then
    CODER_PASSWORD="$(existing_password)"
    CODER_PASSWORD="${CODER_PASSWORD:-$(openssl rand -base64 12)}"
    (umask 077; echo "CODER_PASSWORD=${CODER_PASSWORD}" >> .env)
  fi
fi
export CODER_PASSWORD

# The container's ubuntu user needs the socket's group to talk to the host daemon
setting DOCKER_GID "$(stat -c %g "${DOCKER_SOCK}" 2>/dev/null || stat -f %g "${DOCKER_SOCK}" 2>/dev/null || echo 999)"

# Dashboard login: admin / CODER_PASSWORD, as an htpasswd entry
export TRAEFIK_AUTH="admin:$(openssl passwd -apr1 "${CODER_PASSWORD}")"

# Local CA (certs/ca.crt, trust it once in your browser/OS) that signs the cert Traefik serves for
# DEVBOX_HOST, TRAEFIK_HOST and PORTAINER_HOST via traefik/dynamic/tls.yml; the cert is reissued if a host changes
mkdir -p certs
if [[ ! -f certs/ca.crt ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=devbox local CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout certs/ca.key -out certs/ca.crt 2>/dev/null
  chmod 600 certs/ca.key
  rm -f certs/devbox.crt
fi
cert_covers() { openssl x509 -in certs/devbox.crt -noout -checkhost "$1" 2>/dev/null | grep -q 'does match'; }
extra_hosts_covered() { local h; for h in ${EXTRA_HOSTS//,/ }; do cert_covers "$h" || return 1; done; }
if ! openssl verify -CAfile certs/ca.crt certs/devbox.crt >/dev/null 2>&1 \
  || ! cert_covers "${DEVBOX_HOST}" \
  || ! cert_covers "${TRAEFIK_HOST}" \
  || ! cert_covers "${PORTAINER_HOST}" \
  || ! openssl x509 -in certs/devbox.crt -noout -ext subjectAltName 2>/dev/null | grep -q '\*\.localhost' \
  || ! extra_hosts_covered; then
  SAN="subjectAltName=DNS:localhost,DNS:*.localhost,DNS:${DEVBOX_HOST},DNS:${TRAEFIK_HOST},DNS:${PORTAINER_HOST}"
  for h in ${EXTRA_HOSTS//,/ }; do SAN+=",DNS:${h}"; done
  openssl req -newkey rsa:2048 -nodes -subj "/CN=${DEVBOX_HOST}" \
    -keyout certs/devbox.key -out certs/devbox.csr 2>/dev/null
  openssl x509 -req -in certs/devbox.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
    -days 825 -extfile <(printf '%s\nextendedKeyUsage=serverAuth\n' "${SAN}") -out certs/devbox.crt 2>/dev/null
  chmod 600 certs/devbox.key
  rm -f certs/devbox.csr
  cat > traefik/dynamic/tls.yml <<'TLS'
tls:
  certificates:
    - certFile: /certs/devbox.crt
      keyFile: /certs/devbox.key
TLS
fi

# Portainer creates its admin user from this file, so there is no setup-token screen (min. 12 characters)
mkdir -p secrets
(umask 077; printf '%s' "${CODER_PASSWORD}" > secrets/portainer_admin_password)

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
echo "URL:      https://${DEVBOX_HOST}${HTTPS_SUFFIX}  (trust certs/ca.crt once to remove the browser warning)"
echo "Traefik:  https://${TRAEFIK_HOST}${HTTPS_SUFFIX}  (user: admin, same password)"
echo "Portainer: https://${PORTAINER_HOST}${HTTPS_SUFFIX}  (user: admin, same password)"
echo "Password: ${CODER_PASSWORD}"
echo "--------------------------------------------------------"
