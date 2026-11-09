#!/usr/bin/env bash
# Package lifecycle checks: run only in a disposable Debian container/VM.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sh "$(dirname "${BASH_SOURCE[0]}")/configure-apt.sh"
cd "${1:-/packages}"
shopt -s nullglob
packages=(./led-ugreen-dkms_*.deb ./led-ugreen-cli_*.deb ./led-ugreen-utils_*.deb ./led-ugreen-systemd_*.deb)
((${#packages[@]} == 4)) || { echo 'Expected exactly four packages' >&2; exit 1; }

assert_installed() {
    local package
    for package in led-ugreen-{dkms,cli,utils,systemd}; do
        [[ $(dpkg-query -W -f='${Status}' "$package") = 'install ok installed' ]]
    done
}
preseed() {
    debconf-set-selections <<SEEDS
led-ugreen-systemd led-ugreen-systemd/configure-services boolean true
led-ugreen-systemd led-ugreen-systemd/network-mode select multi
led-ugreen-systemd led-ugreen-systemd/network-interface string enp2s0 enp3s0
led-ugreen-systemd led-ugreen-systemd/enable-services boolean $1
SEEDS
}
assert_no_enablement() {
    [[ -z $(find /etc/systemd/system -type l -name 'ugreen-*' -print 2>/dev/null) ]]
}
apt-get update
apt-get install -y --no-install-recommends debconf-utils
preseed false
apt-get install -y --no-install-recommends "${packages[@]}"
assert_installed
assert_no_enablement
[[ -f /usr/src/led-ugreen-0.3/dkms.conf ]]
[[ -f /usr/lib/modules-load.d/led-ugreen.conf ]]
[[ -f /usr/lib/systemd/system/ugreen-netdevmon-multi.service || -f /lib/systemd/system/ugreen-netdevmon-multi.service ]]
! dpkg-query -L led-ugreen-systemd | grep -q '^/etc/systemd/system/.*\.service$'
ugreen_leds_cli >/dev/null
for command in ugreen-blink-disk ugreen-check-standby ugreen-detect-disks ugreen-detect-network ugreen-diskiomon ugreen-netdevmon ugreen-netdevmon-multi ugreen-power-led ugreen-probe-leds; do
    command -v "$command" >/dev/null
done
# Check shared libraries without touching any LED or disk hardware.
for command in ugreen_leds_cli ugreen-blink-disk ugreen-check-standby; do
    output=$(ldd "$(command -v "$command")")
    ! grep -q 'not found' <<<"$output"
done
printf '\nMAPPING_METHOD=serial\nLED_INVERT=0\n' >>/etc/ugreen-leds.conf
printf '\n# local network choice\n' >>/etc/ugreen-leds/network.conf
before=$(sha256sum /etc/ugreen-leds.conf /etc/ugreen-leds/network.conf)
# An administrator enables just one service. Reinstall/reconfigure must neither
# disable it nor enable any of the others, even with a changed debconf answer.
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -s /lib/systemd/system/ugreen-power-led.service /etc/systemd/system/multi-user.target.wants/ugreen-power-led.service
preseed true
apt-get install -y --no-install-recommends --reinstall "${packages[@]}"
dpkg-reconfigure -f noninteractive led-ugreen-systemd
assert_installed
[[ "$before" = "$(sha256sum /etc/ugreen-leds.conf /etc/ugreen-leds/network.conf)" ]]
[[ -L /etc/systemd/system/multi-user.target.wants/ugreen-power-led.service ]]
[[ ! -L /etc/systemd/system/multi-user.target.wants/ugreen-diskiomon.service ]]
apt-get remove -y led-ugreen-systemd
[[ -f /etc/ugreen-leds/network.conf ]]
apt-get install -y --no-install-recommends ./led-ugreen-systemd_*.deb
[[ "$before" = "$(sha256sum /etc/ugreen-leds.conf /etc/ugreen-leds/network.conf)" ]]
apt-get purge -y led-ugreen-systemd led-ugreen-utils led-ugreen-dkms led-ugreen-cli
[[ ! -e /etc/ugreen-leds.conf && ! -e /etc/ugreen-leds/network.conf ]]
[[ ! -e /var/lib/led-ugreen-systemd/configured ]]
assert_no_enablement
# A fresh installation with consent must enable every automatic service, even
# without systemd running as PID 1. Purging must remove all enablement again.
preseed true
apt-get install -y --no-install-recommends "${packages[@]}"
assert_installed
for unit in ugreen-probe-leds ugreen-diskiomon ugreen-power-led ugreen-netdevmon-multi; do
    [[ -L /etc/systemd/system/multi-user.target.wants/$unit.service ]]
done
apt-get purge -y led-ugreen-systemd led-ugreen-utils led-ugreen-dkms led-ugreen-cli
assert_no_enablement
echo 'All package lifecycle checks passed'
