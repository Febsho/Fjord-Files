#!/usr/bin/env python3
"""End-to-end backend checks using an isolated home and temporary files."""
import base64
import json
import os
import shutil
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import unittest
import zipfile

BINARY = Path(__file__).resolve().parents[1] / "core/bin/dfiles"


class BackendAcceptance(unittest.TestCase):
    def test_navigation_copy_move_and_trash(self):
        self.assertTrue(BINARY.is_file(), "build core/bin/dfiles first")
        with tempfile.TemporaryDirectory(prefix="fjord-acceptance-") as tmp:
            root = Path(tmp)
            for name in ("runtime", "home", "config", "cache", "data", "state", "source", "copy", "move"):
                (root / name).mkdir(mode=0o700)
            env = os.environ.copy()
            env.update({"HOME": str(root / "home"), "XDG_RUNTIME_DIR": str(root / "runtime"),
                        "XDG_CONFIG_HOME": str(root / "config"), "XDG_CACHE_HOME": str(root / "cache"),
                        "XDG_DATA_HOME": str(root / "data"), "XDG_STATE_HOME": str(root / "state"),
                        "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/fjord-test-bus",
                        "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=/nonexistent/fjord-test-bus"})
            env.pop("DFILES_SOCKET", None)
            process = subprocess.Popen([str(BINARY), "daemon"], env=env,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            env["DFILES_SOCKET"] = str(root / "runtime" / f"fjord-files-{process.pid}.sock")

            def call(method, *args):
                response = subprocess.run([str(BINARY), "ipc", method, *args], env=env,
                                          capture_output=True, text=True, timeout=10, check=True)
                return json.loads(response.stdout)

            def job(method, *args):
                job_id = call(method, *args)["job"]["id"]
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    jobs = call("files.op.jobs")["jobs"]
                    match = next((item for item in jobs if item["id"] == job_id), None)
                    if match and match["state"] in ("done", "failed", "cancelled"):
                        self.assertEqual(match["state"], "done", match)
                        self.assertFalse(match.get("cancelled"), match)
                        self.assertEqual(match.get("skipped"), 0, match)
                        self.assertEqual(match.get("warnings"), 0, match)
                        return
                    time.sleep(0.01)
                self.fail(f"job {job_id} did not finish")

            try:
                deadline = time.monotonic() + 10
                while not Path(env["DFILES_SOCKET"]).exists():
                    self.assertIsNone(process.poll(), "daemon exited before startup")
                    self.assertLess(time.monotonic(), deadline, "daemon socket did not appear")
                    time.sleep(0.01)
                if os.geteuid() != 0:
                    denied = root / "source" / "private.txt"
                    denied.write_text("private")
                    denied.chmod(0)
                    error = subprocess.run([str(BINARY), "ipc", "files.preview", f"path={denied}"],
                                           env=env, capture_output=True, text=True, timeout=10)
                    self.assertNotEqual(error.returncode, 0)
                    self.assertIn("permission denied", error.stderr.lower())
                    denied.chmod(0o600)
                    denied.unlink()
                source = root / "source" / "Grüße ; $() [1].txt"
                source.write_bytes(b"fjord\n\x00unicode test\n")
                disguised_text = root / "source" / "notes.png"
                disguised_text.write_text("plain text, despite the extension")
                detected = call("files.viewerFor", f"path={disguised_text}")
                self.assertEqual(detected["viewer"], "text")
                disguised_image = root / "source" / "picture.txt"
                fixture = Path(__file__).resolve().parents[1] / "quickshell/tests/qml/preview.png"
                disguised_image.write_bytes(fixture.read_bytes())
                detected = call("files.viewerFor", f"path={disguised_image}")
                self.assertEqual(detected["viewer"], "image")
                image_preview = call("files.imagePreview", f"path={disguised_image}")
                self.assertEqual((image_preview["fullWidth"], image_preview["fullHeight"]), (1, 1))
                preview_png = base64.b64decode(image_preview["url"].removeprefix("data:image/png;base64,"))
                self.assertEqual(preview_png[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(struct.unpack(">II", preview_png[16:24]), (1, 1))
                archive = root / "source" / "archive.txt"
                with zipfile.ZipFile(archive, "w") as zf:
                    zf.writestr("nested/safe.txt", "hello")
                    zf.writestr("../escape", "not extracted")
                detected = call("files.viewerFor", f"path={archive}")
                self.assertEqual(detected["viewer"], "archive")
                contents = call("files.archiveList", f"path={archive}")
                self.assertEqual([item["path"] for item in contents["entries"]], ["nested/safe.txt"])
                self.assertFalse((root / "escape").exists())
                job("files.op.extractMember", f"path={archive}", "member=nested/safe.txt", f"dest={root / 'copy'}")
                self.assertEqual((root / "copy" / "safe.txt").read_text(), "hello")
                note = root / "source" / "editing.txt"
                note.write_text("original")
                document = call("files.textRead", f"path={note}")
                saved = call("files.textSave", f"path={note}", f"revision={document['revision']}", "text=changed")
                self.assertEqual(note.read_text(), "original")
                self.assertEqual(Path(saved["path"]).read_text(), "changed")
                link = root / "source" / "outside-link"
                link.symlink_to(root / "data", target_is_directory=True)
                analysis = call("storage.scan", f"path={source.parent}", "scanId=acceptance-scan")
                self.assertFalse(analysis["truncated"])
                self.assertGreaterEqual(analysis["skipped"], 1)
                self.assertIn(str(source), [item["path"] for item in analysis["files"]])
                self.assertNotIn(str(link), [item["path"] for item in analysis["files"]])
                project = source.parent / "retired-rust"
                (project / "target").mkdir(parents=True)
                manifest = project / "Cargo.toml"
                source_file = project / "main.rs"
                generated = project / "target" / "build.bin"
                manifest.write_text("[package]\nname = 'example'\n")
                source_file.write_text("fn main() {}\n")
                generated.write_bytes(b"generated build output")
                source_time = time.time() - 5 * 365 * 24 * 60 * 60
                os.utime(manifest, (source_time, source_time))
                os.utime(source_file, (source_time + 3600, source_time + 3600))
                package_json = root / "data" / "package.json"
                package_json.write_text("{}\n")
                projects = call("storage.projects", f"path={source.parent}", "scanId=project-acceptance")
                self.assertFalse(projects["truncated"])
                self.assertFalse(projects["projectsTruncated"])
                self.assertEqual([item["path"] for item in projects["projects"]], [str(project)])
                self.assertEqual(projects["projects"][0]["kinds"], ["Rust"])
                self.assertEqual(projects["projects"][0]["size"], manifest.stat().st_size + source_file.stat().st_size + generated.stat().st_size)
                self.assertAlmostEqual(projects["projects"][0]["lastActivityMs"], int((source_time + 3600) * 1000), delta=1000)
                if shutil.which("sweep", path=env.get("PATH")):
                    history_dir = root / "config" / "sweep"
                    history_dir.mkdir(parents=True, exist_ok=True)
                    history_file = history_dir / "history.jsonl"
                    record = {"ts": "2026-11-15T10:00:00Z", "targetDir": str(root / "source"),
                              "engine": "js", "deleted": 1, "bytesFreed": 42, "failed": 0,
                              "interrupted": False, "trashDir": str(root / "source" / ".sweep-trash")}
                    history_file.write_text(json.dumps(record) + "\n")
                    history = call("sweep.history")
                    self.assertEqual(history["recent"][0]["trashDir"], record["trashDir"])
                    self.assertEqual(json.loads(history_file.read_text()), record)
                listing = call("files.list", f"path={source.parent}")
                self.assertIn(source.name, [item["name"] for item in listing["entries"]])
                job("files.op.copy", f"paths={source}", f"dest={root / 'copy'}")
                copied = root / "copy" / source.name
                self.assertEqual(copied.read_bytes(), source.read_bytes())
                job("files.op.move", f"paths={copied}", f"dest={root / 'move'}")
                moved = root / "move" / source.name
                self.assertFalse(copied.exists())
                self.assertEqual(moved.read_bytes(), source.read_bytes())
                job("files.op.trash", f"paths={moved}")
                self.assertFalse(moved.exists())
                trashed = root / "data" / "Trash" / "files" / source.name
                self.assertEqual(trashed.read_bytes(), source.read_bytes())
                job("files.op.restore", f"names={source.name}", f"trashDir={root / 'data' / 'Trash'}")
                self.assertEqual(moved.read_bytes(), source.read_bytes())
                self.assertFalse(trashed.exists())
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    unittest.main()
