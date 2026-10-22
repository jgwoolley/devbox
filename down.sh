#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# compose.yml requires PASSWORD to be set, even though down doesn't use it
PASSWORD=unused docker compose down --volumes --rmi local
