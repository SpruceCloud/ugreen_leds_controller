#!/usr/bin/env bash
# Compile against a distribution kernel without loading anything into the host.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sh "$(dirname "${BASH_SOURCE[0]}")/configure-apt.sh"
apt-get update
apt-get install -y --no-install-recommends /packages/led-ugreen-dkms_*.deb linux-headers-amd64
found=false
for directory in /lib/modules/*; do
    [[ -d "$directory/build" ]] || continue
    kernel=${directory##*/}
    dkms autoinstall -k "$kernel"
    modinfo -k "$kernel" led-ugreen >/dev/null
    found=true
done
$found || { echo 'No kernel headers found' >&2; exit 1; }
echo 'DKMS kernel compilation checks passed'
