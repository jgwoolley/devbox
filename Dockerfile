FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    git \
    sudo \
    python3 \
    make \
    g++ \
    ca-certificates \
    gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Grant passwordless sudo to built-in 'ubuntu' user and fix home directory permissions
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ubuntu \
    && mkdir -p /home/ubuntu/workspace \
    && chown -R ubuntu:ubuntu /home/ubuntu

USER ubuntu
WORKDIR /home/ubuntu/workspace

EXPOSE 8080

ENTRYPOINT ["code-server", "--bind-addr", "0.0.0.0:8080", "--auth", "password", "/home/ubuntu/workspace"]