"""Exercise launcher recovery/ownership without contacting a phone or network."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "macos/start-usb-proxy.sh"


class USBLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mpp-usb-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        HOME=str(self.root), MOCK_ROOT=str(self.root),
                        MOCK_PID="43210", MOCK_HEALTH="healthy", MOCK_LAUNCH="ok",
                        MPP_BUNDLE_ID="com.example.testproxy")
        self.env["MOCK_COMMAND"] = f"{self.bin}/iproxy -l -s 127.0.0.1 -u TEST-DEVICE 8889:8888"
        self.mock("lsof", 'import os; print(os.environ.get("MOCK_PID", ""))')
        self.mock("ps", 'import os; print(os.environ["MOCK_COMMAND"])')
        self.mock("sleep", 'import time; time.sleep(0.1)')
        self.mock("curl", '''import os, json
from pathlib import Path
mode=os.environ["MOCK_HEALTH"]
root=Path(os.environ["MOCK_ROOT"])
if mode=="fail" or (mode=="after-launch" and not (root/"launched").exists()):
    raise SystemExit(7)
print(json.dumps({"isRunning": True, "port": 9999 if mode=="wrong-port" else 8888, "build":"9"}))
''')
        self.mock("xcrun", '''import os, sys, json
from pathlib import Path
root=Path(os.environ["MOCK_ROOT"])
(root/"launch-args").write_text(json.dumps(sys.argv[1:]))
if os.environ["MOCK_LAUNCH"]=="fail": raise SystemExit(1)
(root/"launched").touch()
''')
        self.mock("iproxy", '''import os, signal, time
from pathlib import Path
root=Path(os.environ["MOCK_ROOT"])
if os.environ.get("MOCK_PROXY_EXIT"): raise SystemExit(1)
(root/"proxy-pid").write_text(str(os.getpid()))
def stop(*args):
    (root/"proxy-stopped").touch()
    raise SystemExit(0)
signal.signal(signal.SIGTERM, stop)
while True: time.sleep(0.05)
''')

    def mock(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + body + "\n")
        path.chmod(0o755)

    def run_launcher(self, *args):
        return subprocess.run([str(SCRIPT), *(args or ("TEST-DEVICE",))],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def assert_no_restart(self):
        self.assertFalse((self.root / "launch-args").exists())

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        self.fail("Timed out waiting for the mocked tunnel")

    def test_invalid_arguments_do_not_start_anything(self):
        for args in [("bad device",), ("TEST-DEVICE", "0"), ("TEST-DEVICE", "65536"),
                     ("TEST-DEVICE", "08889"), ("TEST-DEVICE", "8889", "abc")]:
            with self.subTest(args=args):
                self.assertEqual(self.run_launcher(*args).returncode, 2)
        self.assert_no_restart()
        self.assertFalse((self.root / "proxy-pid").exists())

    def test_foreign_listener_is_preserved(self):
        self.env["MOCK_COMMAND"] = "some-other-app --port 8889"
        result = self.run_launcher()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Nothing was stopped", result.stderr)
        self.assert_no_restart()

    def test_other_device_tunnel_is_preserved(self):
        self.env["MOCK_COMMAND"] = self.env["MOCK_COMMAND"].replace("TEST-DEVICE", "OTHER-DEVICE")
        self.assertEqual(self.run_launcher().returncode, 1)
        self.assert_no_restart()

    def test_matching_healthy_tunnel_is_reused(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Reusing", result.stdout)
        self.assert_no_restart()
        self.assertFalse((self.root / "proxy-pid").exists())

    def test_only_selected_app_is_restarted_when_unhealthy(self):
        self.env["MOCK_HEALTH"] = "after-launch"
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((self.root / "launch-args").read_text()),
                         ["devicectl", "device", "process", "launch", "--device", "TEST-DEVICE",
                          "--terminate-existing", "--timeout", "15", "com.example.testproxy"])

    def test_wrong_phone_port_is_not_reported_ready(self):
        self.env["MOCK_HEALTH"] = "wrong-port"
        result = self.run_launcher()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Ready:", result.stdout)

    def test_failed_restart_cleans_up_new_tunnel(self):
        self.env.update(MOCK_PID="", MOCK_HEALTH="fail", MOCK_LAUNCH="fail")
        result = self.run_launcher()
        self.assertEqual(result.returncode, 1)
        self.wait_for(lambda: (self.root / "proxy-stopped").exists())

    def test_early_tunnel_exit_is_reported(self):
        self.env["MOCK_PID"] = ""
        # Exit immediately, before the mocked startup delay, without waiting
        # for another Python interpreter to initialize under a busy CI host.
        (self.bin / "iproxy").write_text("#!/bin/sh\nexit 1\n")
        result = self.run_launcher()
        self.assertEqual(result.returncode, 1)
        self.assertIn("iproxy stopped", result.stderr)
        self.assert_no_restart()

    def test_termination_stops_only_the_created_tunnel(self):
        self.env["MOCK_PID"] = ""
        with (self.root / "output").open("w+") as output:
            process = subprocess.Popen([str(SCRIPT), "TEST-DEVICE"], env=self.env,
                                       stdout=output, stderr=subprocess.STDOUT)
            try:
                self.wait_for(lambda: "Ready:" in (self.root / "output").read_text())
                process.send_signal(signal.SIGTERM)
                self.assertEqual(process.wait(timeout=5), 143)
                self.wait_for(lambda: (self.root / "proxy-stopped").exists())
                self.assert_no_restart()
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                pid_file = self.root / "proxy-pid"
                if pid_file.exists() and not (self.root / "proxy-stopped").exists():
                    try:
                        os.kill(int(pid_file.read_text()), signal.SIGTERM)
                    except ProcessLookupError:
                        pass


if __name__ == "__main__":
    unittest.main(verbosity=2)
