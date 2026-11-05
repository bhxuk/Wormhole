# Wormhole - Windows 11 in Docker
# Created by bhxuk.com - https://github.com/bhxuk/Wormhole
FROM debian:bookworm-slim

ARG VERSION=dev
LABEL org.opencontainers.image.title="Wormhole" \
      org.opencontainers.image.description="Windows 11 in a Docker container with RDP and browser access" \
      org.opencontainers.image.vendor="bhxuk.com" \
      org.opencontainers.image.url="https://bhxuk.github.io/Wormhole/" \
      org.opencontainers.image.source="https://github.com/bhxuk/Wormhole" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      qemu-system-x86 qemu-utils ovmf swtpm swtpm-tools \
      novnc websockify python3 genisoimage procps iproute2 ca-certificates tini \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/wormhole/web /storage /iso \
 && cp -r /usr/share/novnc/. /opt/wormhole/web/

COPY src/ /opt/wormhole/
COPY web/ /opt/wormhole/web/
RUN chmod +x /opt/wormhole/entrypoint.sh /opt/wormhole/helper.py \
 && echo "${VERSION}" > /opt/wormhole/VERSION

# Defaults - all can be overridden with environment variables
ENV RAM_SIZE="8G" \
    CPU_CORES="4" \
    DISK_SIZE="64G" \
    USERNAME="wormhole" \
    PASSWORD="wormhole" \
    COMPUTER_NAME="WORMHOLE" \
    EDITION="Pro" \
    LANGUAGE="en-US" \
    REGION="en-US" \
    KEYBOARD="en-US" \
    TIMEZONE="UTC" \
    SHUTDOWN_TIMEOUT="110"

VOLUME ["/storage"]
EXPOSE 8006 3389/tcp 3389/udp

HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
  CMD python3 /opt/wormhole/helper.py health || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/opt/wormhole/entrypoint.sh"]
