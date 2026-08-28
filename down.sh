#!/usr/bin/env bash
set -euo pipefail

docker stop claude-browser-ubuntu && docker rm claude-browser-ubuntu
docker volume rm claude_coder_home 
docker image rm claude-vscode-ubuntu:latest