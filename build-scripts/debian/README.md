# Debian packages

Run from any directory. Docker and Bash are required; `--local` also needs
Python 3 on the host. All builds target Linux amd64, including on ARM Macs.

```bash
# Build the committed HEAD (uncommitted edits are excluded).
./build-scripts/debian/docker-run.sh
# Build an exact commit/tag from this repository; invalid refs fail.
./build-scripts/debian/docker-run.sh v0.3
# Include tracked edits and new nonignored files for development.
./build-scripts/debian/docker-run.sh --local
# Debian 11 (archived), 12 and 13 are supported.
DEBIAN_VERSION=bullseye ./build-scripts/debian/docker-run.sh
DEBIAN_VERSION=trixie ./build-scripts/debian/docker-run.sh
# Build selected packages (combine skips, or use one --only-* option).
./build-scripts/debian/docker-run.sh --only-cli
./build-scripts/debian/docker-run.sh --skip-cli --skip-systemd
```

`--local` cannot be combined with a Git ref. When building an older ref, that
ref must contain a compatible build system. The build cleans its exported copy
and never writes compilation output into the checkout.

Output is in `build-scripts/debian/build/<release>/` (override with `OUTPUT_DIR`).
Debhelper may additionally emit debug-symbol packages. A successful run replaces the previous artifacts for that target. A failed run
returns nonzero and preserves the previous successful output. Do not infer build
success merely from the existence of older files.

All four packages take their version from `debian/changelog` (currently `0.3-2`):

| Package | Architecture | Purpose |
| --- | --- | --- |
| `led-ugreen-dkms_0.3-2_all.deb` | all | Kernel sources, DKMS integration and vendor module autoload defaults |
| `led-ugreen-cli_0.3-2_amd64.deb` | amd64 | Dynamically linked direct-I2C CLI |
| `led-ugreen-utils_0.3-2_amd64.deb` | amd64 | Disk/network monitors and compiled helpers |
| `led-ugreen-systemd_0.3-2_all.deb` | all | Vendor units and optional initial service configuration |

`Architecture: all` describes source/scripts, not support for arbitrary NAS
hardware. This driver probes the Intel I801 SMBus and requires compatible UGREEN
hardware. Install headers matching your running kernel for DKMS; custom kernels
may need their own header package. Secure Boot requires enrollment/signing using
the distribution's DKMS workflow. The CLI requires `i2c-dev` and exclusive I2C
access: unload `led-ugreen` before using it.

## Installation and configuration

Install the four packages together with `apt install ./led-ugreen-*.deb` from the
output directory so APT resolves dependencies. Runtime library minimum versions
are generated from the actual binaries; install packages built for your Debian
release.

Debconf offers initial network mode (`single`, selected `multi`, or `all`) and
whether to enable/start services. Selecting No leaves services disabled. Starting
services respects `policy-rc.d`; installation works without systemd running.

Disk mapping, serial numbers and LED appearance are configured manually in
`/etc/ugreen-leds.conf`, a dpkg conffile that maintainer scripts never rewrite.
Verify disk-to-slot mapping for your NAS before relying on disk LEDs.

Initial network choices are stored in `/etc/ugreen-leds/network.conf`. This file
is preserved on upgrade, reconfigure and removal, and deleted on purge. You may
edit it, or override `NETWORK_MODE` and `NETWORK_INTERFACES` in the main conffile.
Network aggregation polls RX/TX byte counters for every selected interface and
blinks on activity from any of them. `NETDEV_POLL_INTERVAL` defaults to 0.1 seconds;
`NETDEV_BLINK_RX`/`NETDEV_BLINK_TX` select which directions contribute. Automatic
selection considers physical Ethernet devices regardless of interface name.

Upgrades between these packages retain enabled/disabled states and restart only running automatic
services. When migrating from the older manual packages, their old prerm may
disable services before the new package runs; re-enable your chosen services
once after that migration. After initial configuration, use `systemctl enable --now` or
`systemctl disable --now` to change service enablement. Legacy per-interface
`ugreen-netdevmon@.service` remains available for manual single-interface use;
use one network-monitoring method at a time.

## Validation

```bash
# Build, lint, test the package lifecycle, and compile DKMS without hardware.
./build-scripts/debian/build-and-test.sh --local
# Run all supported releases (also covered by GitHub Actions).
for release in bullseye bookworm trixie; do
    DEBIAN_VERSION=$release ./build-scripts/debian/build-and-test.sh --local
done
```

The lifecycle test must run in a disposable container/VM; it installs and purges
packages. It never loads kernel modules or requires a privileged container.
Network regression tests use fake sysfs files and check activity on the slower
NIC, selected interfaces, RX/TX controls and counter resets. Required failures
return nonzero. Lintian errors fail the build.

The test also compiles DKMS against each distribution's amd64 kernel headers
without loading the module. Loading, Secure Boot enrollment and physical LED
behavior need separate VM/device validation. In a disposable VM with matching headers, check
`dkms autoinstall`, `modinfo led-ugreen` and `modprobe led-ugreen`, then run
`ugreen-probe-leds` and confirm the expected sysfs LEDs. On compatible hardware,
verify disk mapping, traffic on each NIC, service restart and reboot behavior.

## Release provenance and reproducibility

The builder emits `.buildinfo`, `.changes`, installed build-package versions and
`build-provenance.txt` alongside the packages. Source exports exclude ignored
artifacts, and `SOURCE_DATE_EPOCH` defaults to the source commit timestamp. Package
versions and the DKMS module version come from the Debian changelog.

Default Debian tags and live APT repositories are mutable. For repeatable release
builds, supply a base-image digest and a Debian snapshot timestamp:

```bash
DEBIAN_VERSION=bookworm \
DEBIAN_IMAGE='debian@sha256:<verified-bookworm-image-digest>' \
DEBIAN_SNAPSHOT='<YYYYMMDDTHHMMSSZ>' \
./build-scripts/debian/docker-run.sh <commit>
```

Keep the image digest, snapshot timestamp and source commit with the release.
The workflow records build inputs; it does not claim bit-for-bit reproduction
without pinned inputs and a comparison of two clean builds.

The scripts `build-*-deb.sh` are compatibility entry points for individual builds
inside a prepared Linux environment. They use the root `debian/` metadata; the
old `kmod/debian/` packaging has been removed.
