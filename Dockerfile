FROM swift:6.4.2-noble

# --------------------------------------------------
# Environment
# --------------------------------------------------
ENV CLAUDE_CONFIG_DIR=/root/.claude \
    PATH="/root/.local/bin:${PATH}"

# --------------------------------------------------
# Basic tools
# --------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      git \
      ripgrep \
      jq \
      less \
      bash \
      unzip \
      zip \
      xz-utils \
      libatomic1 \
      usbmuxd \
      libimobiledevice-utils && \
    rm -rf /var/lib/apt/lists/*

# --------------------------------------------------
# Node.js 26 LTS
# --------------------------------------------------
ARG NODE_VERSION=26.13.0

RUN set -eux; \
    case "$(uname -m)" in \
      aarch64) NODE_ARCH=arm64 ;; \
      x86_64)  NODE_ARCH=x64 ;; \
      *) exit 1 ;; \
    esac; \
    cd /tmp; \
    curl -fsSLO \
      "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"; \
    curl -fsSLO \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"; \
    grep " node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz\$" \
      SHASUMS256.txt | sha256sum -c -; \
    tar -xJf \
      "node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
      -C /usr/local --strip-components=1; \
    rm -f /tmp/SHASUMS256.txt /tmp/node-*.tar.xz; \
    node --version; \
    npm --version

# --------------------------------------------------
# Claude Code (native installer)
# --------------------------------------------------
RUN curl -fsSL https://claude.ai/install.sh | bash

# --------------------------------------------------
# xtool (AppImage, extracted without FUSE)
# --------------------------------------------------
RUN set -eux; \
    mkdir -p /opt/xtool; \
    cd /opt/xtool; \
    curl -fL \
      "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" \
      -o xtool.AppImage; \
    chmod +x xtool.AppImage; \
    ./xtool.AppImage --appimage-extract; \
    ln -s /opt/xtool/squashfs-root/AppRun \
      /usr/local/bin/xtool; \
    rm xtool.AppImage

# --------------------------------------------------
# Workspace
# --------------------------------------------------
WORKDIR /workspace

CMD ["/bin/bash"]
