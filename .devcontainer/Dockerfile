ARG BASE_IMAGE=debian:latest-slim
FROM ${BASE_IMAGE}
# To use an image that already includes Intel oneAPI, build with:
#   docker build --build-arg BASE_IMAGE=intel/oneapi-basekit:latest -f .devcontainer/Dockerfile -t usb-c-soft-network-ci:latest .

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install base dependencies and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    python3 \
    python3-pip \
    git \
    ca-certificates \
    curl \
    wget \
    ca-certificates \
    usbutils \
    pkg-config \
    lsb-release \
    iproute2 \
    usbutils \
    sudo \
 && rm -rf /var/lib/apt/lists/*

# Create a non-root user for development
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME || true \
 && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME || true \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME

WORKDIR /workspaces/usb-c-soft-network

COPY . /workspaces/usb-c-soft-network

RUN chown -R $USERNAME:$USERNAME /workspaces/usb-c-soft-network

# Expose a script that installs Intel oneAPI tools in the container when needed
COPY .devcontainer/setup-oneapi.sh /usr/local/bin/setup-oneapi.sh
RUN chmod +x /usr/local/bin/setup-oneapi.sh

USER $USERNAME

SHELL ["/bin/bash", "-lc"]

CMD ["bash"]
