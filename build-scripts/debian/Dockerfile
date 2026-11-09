ARG DEBIAN_VERSION=bookworm
ARG DEBIAN_IMAGE=debian:${DEBIAN_VERSION}
FROM ${DEBIAN_IMAGE}
ARG DEBIAN_VERSION
ARG DEBIAN_SNAPSHOT=
# Debian 11 uses the archive; optional snapshots pin release build inputs.
COPY configure-apt.sh /usr/local/sbin/ugreen-configure-apt
RUN set -eux; \
    sh /usr/local/sbin/ugreen-configure-apt; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential dpkg-dev debhelper fakeroot dkms python3 git lintian debconf-utils; \
    if [ "$DEBIAN_VERSION" != bullseye ]; then apt-get install -y --no-install-recommends dh-dkms; fi; \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
