#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
release=${DEBIAN_VERSION:-bookworm}
image=${DEBIAN_IMAGE:-debian:$release}
output=${OUTPUT_DIR:-$script_dir/build/$release}
local_source=false
ref=
options=()
while (($#)); do
    case "$1" in
        --local) local_source=true ;;
        --only-*|--skip-*) options+=("$1") ;;
        --*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) [[ -z "$ref" ]] || { echo 'Only one Git ref is accepted' >&2; exit 2; }; ref=$1 ;;
    esac
    shift
done
if $local_source && [[ -n "$ref" ]]; then
    echo '--local cannot be combined with a Git ref' >&2
    exit 2
fi
commit=$(git -C "$repo_root" rev-parse --verify "${ref:-HEAD}^{commit}")
epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repo_root" show -s --format=%ct "$commit")}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/source" "$work/output" "$output"
output=$(cd "$output" && pwd)
if $local_source; then
    # Include tracked edits and new nonignored files, never Git internals or
    # ignored build output. Deleted tracked files are skipped.
    source_id=$(python3 "$script_dir/export-source.py" "$repo_root" "$work/source" "$epoch")
else
    source_id=$(git -C "$repo_root" rev-parse "$commit^{tree}")
    git -C "$repo_root" archive "$commit" | tar -xf - -C "$work/source"
fi
docker build --platform linux/amd64 --build-arg "DEBIAN_IMAGE=$image" \
    --build-arg "DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT:-}" \
    --build-arg "DEBIAN_VERSION=$release" --tag "ugreen-build:$release" "$script_dir"
docker run --rm --platform linux/amd64 \
    --mount "type=bind,source=$work/source,target=/source,readonly" \
    --mount "type=bind,source=$work/output,target=/output" \
    -e "SOURCE_DATE_EPOCH=$epoch" "ugreen-build:$release" \
    bash -euc 'cp -a /source /build/source; cd /build/source
        bash build-scripts/debian/build-all.sh --local "$@"
        lintian --allow-root --fail-on error /build/*.changes
        shopt -s nullglob
        artifacts=(/build/*.deb /build/*.changes /build/*.buildinfo)
        ((${#artifacts[@]})) || { echo "No artifacts produced" >&2; exit 1; }
        cp "${artifacts[@]}" /output/
        dpkg-query -W > /output/build-packages.txt' build ${options[@]+"${options[@]}"}
# Publish only after a successful run; discard previous artifacts for this target.
shopt -s nullglob
packages=("$work/output/"*.deb)
((${#packages[@]})) || { echo 'No packages produced' >&2; exit 1; }
rm -f "$output/"*.deb "$output/"*.changes "$output/"*.buildinfo
cp "$work/output/"* "$output/"
{
    printf 'commit=%s\nsource_id=%s\nlocal_source=%s\nsource_date_epoch=%s\nbase_image=%s\nsnapshot=%s\n' \
        "$commit" "$source_id" "$local_source" "$epoch" "$image" "${DEBIAN_SNAPSHOT:-}"
    docker image inspect "ugreen-build:$release" --format 'builder_image={{.Id}}'
} > "$output/build-provenance.txt"
echo "Build complete: $output"
