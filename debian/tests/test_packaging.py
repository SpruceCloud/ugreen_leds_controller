import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SourceAndBuildTests(unittest.TestCase):
    def test_failed_container_does_not_publish_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "config", "user.email", "test@example.com"], check=True)
            subprocess.run(["git", "-C", str(root), "config", "user.name", "Test"], check=True)
            scripts = root / "build-scripts/debian"
            scripts.mkdir(parents=True)
            shutil.copy(ROOT / "build-scripts/debian/docker-run.sh", scripts)
            (root / "tracked").write_text("committed\n")
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            subprocess.run(["git", "-C", str(root), "commit", "-qm", "fixture"], check=True)
            # Inspect the actual source sent to Docker, then simulate a build
            # failure. The previous successful release must remain untouched.
            (root / "tracked").write_text("uncommitted\n")
            binary = root / "bin"
            binary.mkdir()
            docker = binary / "docker"
            docker.write_text("""#!/usr/bin/env bash
if [[ $1 = run ]]; then
    for argument in "$@"; do
        case "$argument" in
            type=bind,source=*,target=/source,readonly)
                source=${argument#type=bind,source=}
                source=${source%,target=/source,readonly}
                [[ $(cat "$source/tracked") = committed ]] || exit 99
                exit 17 ;;
        esac
    done
fi
exit 0
""")
            docker.chmod(0o755)
            output = root / "output"
            output.mkdir()
            (output / "old.deb").write_text("previous successful build")
            environment = dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}", OUTPUT_DIR=str(output))
            result = subprocess.run(["bash", str(scripts / "docker-run.sh"), "HEAD"],
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 17, result.stderr)
            self.assertEqual((output / "old.deb").read_text(), "previous successful build")
            result = subprocess.run(["bash", str(scripts / "docker-run.sh"), "does-not-exist"],
                                    env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)

    def test_local_build_rejects_git_ref(self):
        result = subprocess.run(["bash", str(ROOT / "build-scripts/debian/build-all.sh"),
                                 "--local", "v0.3"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("cannot be combined", result.stderr)


class MaintscriptTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.log = self.root / "calls"
        self.log.touch()
        self.binary = self.root / "bin"
        self.binary.mkdir()
        helper = self.binary / "deb-systemd-invoke"
        helper.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>"$REVIEW_LOG"\n')
        helper.chmod(0o755)
        systemctl = self.binary / "systemctl"
        systemctl.write_text('#!/bin/sh\n[ "$3" = ugreen-power-led.service ]\n')
        systemctl.chmod(0o755)
        (self.root / "manager").mkdir()

    def run_script(self, name, *arguments):
        script = (ROOT / "debian" / name).read_text()
        script = script.replace('. /usr/share/debconf/confmodule', 'db_stop() { :; }')
        script = script.replace('/run/systemd/system', str(self.root / "manager"))
        script = script.replace('/var/lib/led-ugreen-systemd', str(self.root / "state"))
        target = self.root / "maintscript"
        target.write_text(script)
        result = subprocess.run(["sh", str(target), *arguments], capture_output=True, text=True,
                                env=dict(os.environ, PATH=f"{self.binary}:{os.environ['PATH']}",
                                         REVIEW_LOG=str(self.log)))
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.log.read_text()

    def test_upgrade_restarts_only_active_services(self):
        (self.root / "state").mkdir()
        (self.root / "state/configured").touch()
        calls = self.run_script("led-ugreen-systemd.postinst", "configure", "0.3-2")
        self.assertEqual(calls, "restart ugreen-power-led.service\n")

    def test_removal_stops_all_monitors_but_upgrade_does_not(self):
        self.assertEqual(self.run_script("led-ugreen-systemd.prerm", "upgrade", "0.3-2"), "")
        calls = self.run_script("led-ugreen-systemd.prerm", "remove")
        self.assertIn("ugreen-netdevmon-multi.service", calls)
        self.assertIn("ugreen-netdevmon@*.service", calls)
        self.assertIn("ugreen-diskiomon.service", calls)


@unittest.skipUnless(shutil.which("flock"), "Linux flock is required")
class NetworkTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.net = self.root / "net"
        self.net.mkdir()
        self.led = self.root / "led"
        self.led.mkdir()
        for name in ("trigger", "invert", "delay_on", "delay_off", "brightness", "color", "shot"):
            (self.led / name).touch()
        for name, speed in (("enp1s0", 10000), ("enp2s0", 1000)):
            device = self.net / name
            (device / "device").mkdir(parents=True)
            (device / "statistics").mkdir()
            (device / "type").write_text("1")
            (device / "speed").write_text(str(speed))
            for counter in ("rx_bytes", "tx_bytes"):
                (device / "statistics" / counter).write_text("10")

    def start(self, mode="all", selected="", rx=1, tx=1):
        (self.root / "ugreen-leds.conf").write_text(
            f'NETWORK_MODE={mode}\nNETWORK_INTERFACES="{selected}"\n'
            f'NETDEV_BLINK_RX={rx}\nNETDEV_BLINK_TX={tx}\nNETDEV_POLL_INTERVAL=0.02\n')
        environment = dict(os.environ, UGREEN_NET_ROOT=str(self.net), UGREEN_LED_ROOT=str(self.led),
                           UGREEN_CONFIG_ROOT=str(self.root), UGREEN_RUN_ROOT=str(self.root))
        process = subprocess.Popen(["bash", str(ROOT / "scripts/ugreen-netdevmon-multi")],
                                   env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        def cleanup():
            process.terminate()
            process.communicate(timeout=5)
        self.addCleanup(cleanup)
        self.wait_for(lambda: (self.led / "trigger").read_text().strip() == "oneshot")
        time.sleep(0.1)  # Establish both counter baselines.
        self.assertIsNone(process.poll())
        return process

    def wait_for(self, condition):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.02)
        self.fail("Network monitor did not produce the expected output")

    def test_traffic_on_slower_interface_blinks(self):
        self.start()
        (self.net / "enp2s0/statistics/rx_bytes").write_text("20")
        self.wait_for(lambda: (self.led / "shot").read_text().strip() == "1")

    def test_selection_and_rx_tx_switches(self):
        self.start("multi", "enp2s0", rx=0)
        (self.net / "enp1s0/statistics/tx_bytes").write_text("20")
        (self.net / "enp2s0/statistics/rx_bytes").write_text("20")
        time.sleep(0.15)
        self.assertEqual((self.led / "shot").read_text(), "")
        (self.net / "enp2s0/statistics/tx_bytes").write_text("20")
        self.wait_for(lambda: (self.led / "shot").read_text().strip() == "1")

    def test_counter_reset_is_not_activity(self):
        self.start()
        (self.net / "enp2s0/statistics/rx_bytes").write_text("0")
        time.sleep(0.15)
        self.assertEqual((self.led / "shot").read_text(), "")


if __name__ == "__main__":
    unittest.main()
