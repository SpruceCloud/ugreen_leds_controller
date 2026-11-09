#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
release=${DEBIAN_VERSION:-bookworm}
export OUTPUT_DIR=${OUTPUT_DIR:-$script_dir/build/$release}
"$script_dir/docker-run.sh" "$@"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
docker run --rm --platform linux/amd64 \
    --mount "type=bind,source=$OUTPUT_DIR,target=/packages,readonly" \
    --mount "type=bind,source=$script_dir/test-install.sh,target=/test-install.sh,readonly" \
    --mount "type=bind,source=$script_dir/configure-apt.sh,target=/configure-apt.sh,readonly" \
    -e "DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT:-}" "${DEBIAN_IMAGE:-debian:$release}" bash /test-install.sh

docker run --rm --platform linux/amd64 \
    --mount "type=bind,source=$OUTPUT_DIR,target=/packages,readonly" \
    --mount "type=bind,source=$script_dir/test-dkms.sh,target=/test-dkms.sh,readonly" \
    --mount "type=bind,source=$script_dir/configure-apt.sh,target=/configure-apt.sh,readonly" \
    -e "DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT:-}" "${DEBIAN_IMAGE:-debian:$release}" bash /test-dkms.sh
