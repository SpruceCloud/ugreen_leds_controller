#!/bin/sh
set -eu
. /etc/os-release
if [ -n "${DEBIAN_SNAPSHOT:-}" ]; then
    rm -f /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s/ %s main\n' "$DEBIAN_SNAPSHOT" "$VERSION_CODENAME" >/etc/apt/sources.list
elif [ "$VERSION_CODENAME" = bullseye ]; then
    # Debian 11 has moved to the archive, including its security updates.
    rm -f /etc/apt/sources.list.d/debian.sources
    cat >/etc/apt/sources.list <<'SOURCES'
deb [check-valid-until=no] http://archive.debian.org/debian bullseye main
deb [check-valid-until=no] http://archive.debian.org/debian-security bullseye-security main
SOURCES
fi
