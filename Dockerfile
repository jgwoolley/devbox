FROM ubuntu:24.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies, Node.js repository, and build tools
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

# Install code-server (VS Code in the browser)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install Claude Code globally via npm
RUN npm install -g @anthropic-ai/claude-code

# Create a non-root user 'coder' with sudo privileges
RUN useradd -m -s /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder

USER coder
WORKDIR /home/coder/workspace

# Expose port 8080 for web-based VS Code
EXPOSE 8080

# Launch code-server bound to all interfaces
CMD ["code-server", "--bind-addr", "0.0.0.0:8080", "/home/coder/workspace"]