#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "WARNING: This script is for deleting the Docker volumes for this project."
echo "All data stored in those volumes will be permanently lost."
read -r -p "Type 'delete volumes' to continue: " confirm

if [[ "$confirm" != "delete volumes" ]]; then
  echo "Aborted. Nothing was deleted."
  exit 1
fi

# compose.yml requires CODER_PASSWORD to be set, even though down doesn't use it
CODER_PASSWORD=unused docker compose down --volumes --rmi local