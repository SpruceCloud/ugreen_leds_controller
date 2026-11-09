#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
local_build=false
ref=
packages=(dkms cli utils systemd)
while (($#)); do
    case "$1" in
        --local) local_build=true ;;
        --only-dkms|--only-cli|--only-utils|--only-systemd) packages=("${1#--only-}") ;;
        --skip-dkms|--skip-cli|--skip-utils|--skip-systemd)
            remaining=()
            for package in "${packages[@]}"; do
                [[ "$package" = "${1#--skip-}" ]] || remaining+=("$package")
            done
            packages=("${remaining[@]}") ;;
        --*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) [[ -z "$ref" ]] || { echo 'Only one Git ref is accepted' >&2; exit 2; }; ref=$1 ;;
    esac
    shift
done
((${#packages[@]})) || { echo 'No packages selected' >&2; exit 2; }
if $local_build; then
    [[ -z "$ref" ]] || { echo '--local cannot be combined with a Git ref' >&2; exit 2; }
else
    # Delegate source selection to the host wrapper rather than cloning a
    # different repository or silently ignoring a ref.
    excluded=()
    for package in dkms cli utils systemd; do
        case " ${packages[*]} " in
            *" $package "*) ;;
            *) excluded+=("--skip-$package") ;;
        esac
    done
    exec build-scripts/debian/docker-run.sh "${ref:-HEAD}" ${excluded[@]+"${excluded[@]}"}
fi
export DH_OPTIONS=
for package in "${packages[@]}"; do
    DH_OPTIONS+=" -pled-ugreen-$package"
done
# Start from a clean tree even if invoked on a working-tree export.
debian/rules clean
dpkg-buildpackage -b -us -uc -tc
