#!/usr/bin/env python3
"""Exercise opt-in FileManager1 activation on an isolated session bus."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ActivationTest(unittest.TestCase):
    def test_activation_without_touching_the_real_session(self):
        with tempfile.TemporaryDirectory(prefix="fjord-dbus-test-") as tmp:
            base = Path(tmp)
            prefix = base / "prefix"
            env = os.environ.copy()
            for key in list(env):
                if key.startswith(("DFILES_", "QS_")) or key in ("WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS"):
                    env.pop(key, None)
            env.update({"HOME": str(base / "home"), "XDG_CONFIG_HOME": str(base / "config"),
                        "XDG_CACHE_HOME": str(base / "cache"), "XDG_STATE_HOME": str(base / "state"),
                        "XDG_DATA_HOME": str(base / "data"), "XDG_DATA_DIRS": str(prefix / "share"),
                        "XDG_RUNTIME_DIR": str(base / "runtime"), "QT_QPA_PLATFORM": "offscreen"})
            for name in ("home", "runtime", "data"):
                (base / name).mkdir(mode=0o700)
            subprocess.run(["make", "install", f"PREFIX={prefix}"], cwd=ROOT, env=env, check=True, capture_output=True)
            service = prefix / "share/dbus-1/services/io.github.febsho.fjordfiles.FileManager1.service"
            self.assertFalse(service.exists(), "activation must be opt-in")
            subprocess.run(["make", "install-dbus-activation", f"PREFIX={prefix}"], cwd=ROOT, env=env, check=True, capture_output=True)
            original = service.read_bytes()
            second = subprocess.run(["make", "install-dbus-activation", f"PREFIX={prefix}"], cwd=ROOT, env=env, capture_output=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(service.read_bytes(), original)
            script = r'''
import glob, os, subprocess, sys, time
from pathlib import Path
root = Path(sys.argv[1])
binary = sys.argv[2]
try:
    call = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
        "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowFolders",
        "['file:///tmp']", ""], capture_output=True, text=True, timeout=20)
    if call.returncode or call.stdout.strip() != "()":
        print(call.stdout, call.stderr, file=sys.stderr)
        sys.exit(1)
    print("FileManager1 activation and ShowFolders succeeded")
finally:
    sockets = glob.glob(str(root / "runtime" / "fjord-files-*.sock"))
    for socket in sockets:
        env = os.environ.copy()
        env["DFILES_SOCKET"] = socket
        try:
            subprocess.run([binary, "ipc", "ui.quit"], env=env, capture_output=True, timeout=4)
        except subprocess.SubprocessError:
            pass
'''
            result = subprocess.run(["dbus-run-session", "--", sys.executable, "-c", script,
                                     str(base), str(prefix / "bin" / "fjord-files")], env=env,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("activation and ShowFolders succeeded", result.stdout)


if __name__ == "__main__":
    unittest.main()
