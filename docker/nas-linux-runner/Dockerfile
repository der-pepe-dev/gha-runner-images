# Beefy Linux GitHub Actions runner for the TrueNAS NAS group (Docker app, shares the GPU).
# CUDA devel base gives nvcc + CUDA libs so GPU jobs can build AND run; the TrueNAS nvidia
# runtime injects the host driver. Set CUDA_BASE to a -runtime image (or a plain ubuntu) if
# you don't need nvcc / GPU.
ARG CUDA_BASE=nvidia/cuda:12.6.2-devel-ubuntu24.04
FROM ${CUDA_BASE}

ARG RUNNER_VERSION=2.335.1
ARG DOTNET_CHANNEL=10.0
ENV DEBIAN_FRONTEND=noninteractive

# CI toolchain (mirrors the Proxmox linux image): build tooling + Native AOT prereqs.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential clang zlib1g-dev cmake ninja-build mingw-w64 binutils gdb \
      git curl wget unzip zip jq ca-certificates pkg-config sqlite3 ffmpeg \
      python3 python3-pip python3-venv sudo gnupg apt-transport-https \
 && rm -rf /var/lib/apt/lists/*

# .NET 10 SDK + PowerShell 7 (Microsoft feed) + Node.js LTS (NodeSource).
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o /tmp/ms.deb \
 && dpkg -i /tmp/ms.deb && rm -f /tmp/ms.deb && apt-get update \
 && apt-get install -y "dotnet-sdk-${DOTNET_CHANNEL}" powershell \
 && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
 && apt-get install -y nodejs \
 && rm -rf /var/lib/apt/lists/*

# Non-root runner user; video/render groups so it can reach the shared GPU.
RUN useradd -m -s /bin/bash runner && usermod -aG video,render runner

# Actions runner package (unregistered).
RUN mkdir -p /opt/actions-runner && cd /opt/actions-runner \
 && curl -fsSL -o runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && tar xzf runner.tar.gz && rm -f runner.tar.gz \
 && ./bin/installdependencies.sh \
 && mkdir -p /opt/actions-runner/_work \
 && chown -R runner:runner /opt/actions-runner

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER runner
WORKDIR /opt/actions-runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
