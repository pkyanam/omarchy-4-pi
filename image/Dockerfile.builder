FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install --yes --no-install-recommends \
    ca-certificates \
    curl \
    dosfstools \
    e2fsprogs \
    git \
    gnupg \
    libarchive-tools \
    parted \
    rsync \
    udev \
    util-linux \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
