FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Telemetry opt-outs
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    DOTNET_TELEMETRY_OPTOUT=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1

# Base tooling + Node.js 22 + Java 21 (JDK) + Maven + .NET runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    sudo \
    python3 \
    make \
    g++ \
    ca-certificates \
    gnupg \
    unzip \
    # Java + Maven
    openjdk-21-jdk-headless \
    maven \
    # .NET native dependencies
    libicu74 \
    libssl3 \
    zlib1g \
    libgssapi-krb5-2 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Arch-neutral JAVA_HOME (works on amd64 and arm64)
RUN ln -s "$(dirname "$(dirname "$(readlink -f "$(which javac)")")")" /usr/lib/jvm/java-home
ENV JAVA_HOME=/usr/lib/jvm/java-home

# Install .NET 10 SDK via Microsoft's official install script (system-wide)
ENV DOTNET_ROOT=/usr/share/dotnet
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Grant passwordless sudo to built-in 'ubuntu' user and fix home directory permissions
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ubuntu \
    && mkdir -p /home/ubuntu/workspace \
    && chown -R ubuntu:ubuntu /home/ubuntu

USER ubuntu
WORKDIR /home/ubuntu/workspace
ENV PATH="/home/ubuntu/.local/bin:/home/ubuntu/.dotnet/tools:${PATH}"

# Install Claude Code via the native installer (installs under ~/.local, no root/sudo needed,
# so the ubuntu user can self-update without hitting npm global folder permission errors)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Optional: VS Code extensions from Open VSX (code-server's marketplace)
RUN code-server --install-extension nf3t.nifi-flowfile-extension || true

# Disable editor + extension telemetry in code-server user settings
RUN mkdir -p /home/ubuntu/.local/share/code-server/User \
    && printf '%s\n' \
    '{' \
    '  "telemetry.telemetryLevel": "off",' \
    '  "redhat.telemetry.enabled": false,' \
    '  "csharp.telemetry.enabled": false,' \
    '  "dotnetAcquisitionExtension.enableTelemetry": false' \
    '}' > /home/ubuntu/.local/share/code-server/User/settings.json

# Sanity check
RUN dotnet --version && java -version && mvn -version

EXPOSE 8080

ENTRYPOINT ["code-server", "--bind-addr", "0.0.0.0:8080", "--auth", "password", "--disable-telemetry", "/home/ubuntu/workspace"]