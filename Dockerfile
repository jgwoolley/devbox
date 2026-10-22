FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Telemetry opt-outs
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    DOTNET_TELEMETRY_OPTOUT=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1

# Base tooling + Node.js 22 + Java 21 (JDK) + .NET runtime dependencies
# (apt maven removed: SDKMAN manages Maven/Gradle now. zip is required by SDKMAN.)
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
    zip \
    # Java
    openjdk-21-jdk-headless \
    # jpackage --type deb (fakeroot, dpkg-deb; binutils provides objcopy)
    fakeroot \
    binutils \
    # .NET native dependencies
    libicu74 \
    libssl3 \
    zlib1g \
    libgssapi-krb5-2 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# pnpm/yarn via Corepack (bundled with Node 22). Skip the interactive download prompt.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable

# Arch-neutral JAVA_HOME (works on amd64 and arm64)
RUN ln -s "$(dirname "$(dirname "$(readlink -f "$(which javac)")")")" /usr/lib/jvm/java-home
ENV JAVA_HOME=/usr/lib/jvm/java-home

# GitHub CLI
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI + compose/buildx plugins (no daemon: the host socket is mounted in, see compose.yml)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# Apache NiFi Toolkit (check the NiFi downloads page and set the current version)
ARG NIFI_VERSION=2.12.0
RUN curl -fsSL --retry 5 --retry-delay 5 --connect-timeout 30 --max-time 900 \
      "https://dlcdn.apache.org/nifi/${NIFI_VERSION}/nifi-toolkit-${NIFI_VERSION}-bin.zip" \
      -o /tmp/nifi-toolkit.zip \
    && unzip -q /tmp/nifi-toolkit.zip -d /opt \
    && ln -s "/opt/nifi-toolkit-${NIFI_VERSION}" /opt/nifi-toolkit \
    && chmod -R a+rX "/opt/nifi-toolkit-${NIFI_VERSION}" \
    && chmod a+x "/opt/nifi-toolkit-${NIFI_VERSION}/bin/*.sh" \
    && ln -s /opt/nifi-toolkit/bin/cli.sh /usr/local/bin/nifi-toolkit \
    && rm /tmp/nifi-toolkit.zip
ENV NIFI_TOOLKIT_HOME=/opt/nifi-toolkit

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
# SDKMAN lives outside /home/ubuntu: that path is a mounted volume (see up.sh) which would hide it
RUN mkdir -p /opt/sdkman && chown ubuntu:ubuntu /opt/sdkman

USER ubuntu
WORKDIR /home/ubuntu/workspace

# SDKMAN-managed tools are on PATH for every shell (RUN steps, Claude Code, terminals),
# not just interactive shells that source sdkman-init.sh.
ENV SDKMAN_DIR=/opt/sdkman
ENV PATH="${SDKMAN_DIR}/candidates/maven/current/bin:${SDKMAN_DIR}/candidates/gradle/current/bin:${NIFI_TOOLKIT_HOME}/bin:/home/ubuntu/.local/bin:/home/ubuntu/.dotnet/tools:${PATH}"

# SDKMAN + Maven + Gradle (unpinned = latest; pin with e.g. `sdk install maven 3.9.11`)
RUN curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash \
    && echo 'sdkman_auto_answer=true' >> "${SDKMAN_DIR}/etc/config" \
    && echo 'sdkman_auto_env=false' >> "${SDKMAN_DIR}/etc/config" \
    && bash -c "source ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk install maven && sdk install gradle" \
    && printf '\nexport SDKMAN_DIR="%s"\n[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"\n' "${SDKMAN_DIR}" >> /home/ubuntu/.bashrc

# Pre-fetch pnpm so the first `pnpm` call doesn't need the network.
# Projects with a "packageManager" field in package.json still get their pinned version.
RUN corepack prepare pnpm@latest --activate

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
RUN dotnet --version && java -version && mvn -version && gradle --version && pnpm --version && gh --version && docker --version && docker compose version

EXPOSE 8080

ENTRYPOINT ["code-server", "--bind-addr", "0.0.0.0:8080", "--auth", "password", "--disable-telemetry", "/home/ubuntu/workspace"]