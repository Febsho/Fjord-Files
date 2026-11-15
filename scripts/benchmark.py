#!/usr/bin/env python3
"""Small, isolated daemon benchmarks. Results are JSON on stdout."""
import argparse
import hashlib
import json
import os
import platform
import signal
import select
import shutil
import struct
import zlib
import statistics
import subprocess
import tempfile
import time
from pathlib import Path


def bounded(value, maximum):
    number = int(value)
    if not 1 <= number <= maximum:
        raise argparse.ArgumentTypeError(f"must be between 1 and {maximum}")
    return number


def command_output(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=5).strip()
    except (OSError, subprocess.SubprocessError):
        return None


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def make_png(path):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    width = height = 512
    rows = b"".join(b"\0" + b"".join(bytes(((x + y) % 256, x % 256, y % 256)) for x in range(width)) for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def sample(call, repeats):
    values = []
    for _ in range(repeats):
        start = time.perf_counter_ns()
        call()
        values.append((time.perf_counter_ns() - start) / 1_000_000)
    return {"unit": "ms", "samples": values, "median": statistics.median(values)}


def gui_start(launcher, env):
    """Measure launch until Umbriel reports a newly mapped Fjord window."""
    if not env.get("WAYLAND_DISPLAY"):
        raise RuntimeError("GUI startup requires an active Wayland session")
    if not shutil.which("umbriel"):
        raise RuntimeError("GUI startup measurement requires the Umbriel window observer")

    observer = subprocess.Popen(["umbriel", "subscribe", "windows"], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=1)
    log = tempfile.TemporaryFile(mode="w+t")
    try:
        baseline = json.loads(observer.stdout.readline())
        existing = {w.get("id") for w in baseline.get("data", [])}
        start = time.perf_counter_ns()
        # Run an owned foreground session so this benchmark cannot forward a
        # launch request to another Fjord instance or leave a detached daemon.
        app = subprocess.Popen([str(launcher), "run", "--session"], env=env, stdout=log,
                               stderr=log, start_new_session=True)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if app.poll() is not None:
                log.seek(0)
                raise RuntimeError(f"GUI session exited before a window appeared ({app.returncode}): {log.read()[-3000:]}")
            ready, _, _ = select.select([observer.stdout], [], [], 0.1)
            if not ready:
                continue
            line = observer.stdout.readline()
            if not line:
                raise RuntimeError("Umbriel window observer stopped")
            for window in json.loads(line).get("data", []):
                app_id = window.get("app_id", "").lower()
                title = window.get("title", "").lower()
                if (window.get("id") not in existing and window.get("visible") and
                        ("fjord" in app_id or "fjord files" in title or app_id == "dev.duxlabs.files")):
                    return (time.perf_counter_ns() - start) / 1_000_000
        log.seek(0)
        raise TimeoutError(f"no newly mapped, visible Fjord Files window within 30 seconds: {log.read()[-3000:]}")
    finally:
        if "app" in locals():
            try:
                os.killpg(app.pid, signal.SIGTERM)
                if app.poll() is None:
                    app.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(app.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                app.wait()
        observer.terminate()
        try:
            observer.wait(timeout=2)
        except subprocess.TimeoutExpired:
            observer.kill()
            observer.wait()
        log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path, help="built dfiles binary")
    parser.add_argument("--files", type=lambda s: bounded(s, 100000), default=1000)
    parser.add_argument("--repeats", type=lambda s: bounded(s, 100), default=5)
    parser.add_argument("--large-mib", type=lambda s: bounded(s, 512), default=16, help="size of the large copy fixture in MiB")
    parser.add_argument("--temp-parent", type=Path, help="filesystem for isolated fixtures (default: system temp)")
    parser.add_argument("--gui-launcher", type=Path, help="optional AppImage or launcher to measure until its window is mapped by Umbriel")
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    gui_launcher = args.gui_launcher.resolve(strict=True) if args.gui_launcher else None
    with tempfile.TemporaryDirectory(prefix="fjord-bench-", dir=args.temp_parent) as temp:
        root = Path(temp)
        dirs = {key: root / key for key in ("runtime", "config", "cache", "data", "state", "home", "fixtures")}
        for directory in dirs.values():
            directory.mkdir(mode=0o700)
        env = os.environ.copy()
        for name in ("DBUS_SESSION_BUS_ADDRESS", "DBUS_SYSTEM_BUS_ADDRESS", "DFILES_SOCKET", "FLATPAK_ID"):
            env.pop(name, None)
        env.update({"HOME": str(dirs["home"]), "XDG_RUNTIME_DIR": str(dirs["runtime"]),
                    "XDG_CONFIG_HOME": str(dirs["config"]), "XDG_CACHE_HOME": str(dirs["cache"]),
                    "XDG_DATA_HOME": str(dirs["data"]), "XDG_STATE_HOME": str(dirs["state"]),
                    "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/fjord-benchmark-bus",
                    "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=/nonexistent/fjord-benchmark-bus"})
        fixture = dirs["fixtures"] / "directory"
        fixture.mkdir()
        for i in range(args.files):
            (fixture / f"entry-{i:06d}.txt").write_text("fjord benchmark\n")
        large = dirs["fixtures"] / "large.bin"
        with large.open("wb") as out:
            for _ in range(args.large_mib):
                out.write(bytes(range(256)) * 4096)
        small = dirs["fixtures"] / "small"
        small.mkdir()
        for i in range(min(args.files, 1000)):
            (small / f"file-{i:06d}").write_text("fjord copy benchmark\n")
        copies = dirs["fixtures"] / "copies"
        copies.mkdir()
        thumb_source = dirs["fixtures"] / "thumb-source.png"
        make_png(thumb_source)
        thumbs = []
        for i in range(args.repeats + 1):
            target = dirs["fixtures"] / f"thumb-{i}.png"
            shutil.copyfile(thumb_source, target)
            thumbs.append(target)
        sweep_project = dirs["fixtures"] / "sweep-project"
        (sweep_project / "node_modules").mkdir(parents=True)
        (sweep_project / "package.json").write_text('{"name":"fjord-benchmark"}')
        (sweep_project / "node_modules" / "fixture.bin").write_bytes(b"fjord")
        preview = dirs["fixtures"] / "preview.txt"
        preview.write_text("fjord benchmark text\n" * 1024)
        cpu = next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), None)
        result = {"conditions": {"platform": platform.platform(), "cpu": cpu,
                  "logical_cpus": os.cpu_count(), "mem_total": next((s for s in Path("/proc/meminfo").read_text().splitlines() if s.startswith("MemTotal:")), None),
                  "filesystem": command_output(["findmnt", "-T", str(root), "-no", "FSTYPE,OPTIONS"]),
                  "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                  "gui_launcher_sha256": file_sha256(gui_launcher) if gui_launcher else None,
                  "binary_version": command_output([str(binary), "version"]),
                  "python_version": platform.python_version(),
                  "sweep_version": command_output(["sweep", "--version"]),
                  "sweep_sha256": file_sha256(shutil.which("sweep")) if shutil.which("sweep") else None,
                  "fixture_files": args.files, "fixture_bytes_each": 16, "repeats": args.repeats,
                  "large_copy_mib": args.large_mib, "small_copy_files": min(args.files, 1000),
                  "cache": "uncontrolled; fixture creation and warmup precede samples", "bus": "isolated/unavailable", "timing": "wall-clock including CLI startup and IPC"}, "measurements": {},
                  "not_measured": {"GUI startup": "headless daemon only; no window or rendering measured",
                  "Sweep scans": "sweep executable was not found in PATH"}}
        started = time.perf_counter_ns()
        daemon = subprocess.Popen([str(binary), "daemon"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        socket = None
        def call(method, *params):
            completed = subprocess.run([str(binary), "ipc", method, *params], env=env, capture_output=True, text=True, timeout=30, check=True)
            return json.loads(completed.stdout)
        try:
            deadline = time.monotonic() + 15
            while socket is None:
                if daemon.poll() is not None:
                    raise RuntimeError(f"daemon exited: {daemon.returncode}")
                if time.monotonic() >= deadline:
                    raise TimeoutError("daemon socket not ready")
                sockets = list(dirs["runtime"].glob(f"*-{daemon.pid}.sock"))
                if sockets:
                    socket = sockets[0]
                    env["DFILES_SOCKET"] = str(socket)
                    break
                time.sleep(0.005)
            call("ping")
            result["measurements"]["daemon_start_ready_ms"] = (time.perf_counter_ns() - started) / 1_000_000
            time.sleep(1)
            status = Path(f"/proc/{daemon.pid}/status").read_text()
            result["measurements"]["daemon_idle_rss"] = next((line for line in status.splitlines() if line.startswith("VmRSS:")), None)
            listed = call("files.list", f"path={fixture}", "limit=500")
            if not isinstance(listed, dict) or len(listed.get("entries", [])) != min(args.files, 500):
                raise ValueError("unexpected directory listing")
            result["measurements"]["directory_first_page"] = sample(lambda: call("files.list", f"path={fixture}", "limit=500"), args.repeats)
            checked = call("files.preview", f"path={preview}")
            if not isinstance(checked, dict) or checked.get("binary") or not checked.get("text", "").startswith("fjord benchmark"):
                raise ValueError("unexpected preview")
            result["measurements"]["text_preview_head"] = sample(lambda: call("files.preview", f"path={preview}"), args.repeats)

            thumb_index = 0
            def thumbnail():
                nonlocal thumb_index
                source = thumbs[thumb_index]
                thumb_index += 1
                deadline = time.monotonic() + 30
                while True:
                    response = call("files.thumbnail", f"paths={source}", "size=normal")
                    entries = response.get("results", [])
                    name = entries[0].get("thumbnail", "") if entries else ""
                    if name and Path(name).is_file():
                        if Path(name).read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                            raise ValueError("thumbnail is not a PNG")
                        return
                    if time.monotonic() >= deadline:
                        raise TimeoutError("thumbnail generation did not finish")
                    time.sleep(0.01)
            thumbnail()
            result["measurements"]["thumbnail_generate_512px"] = sample(thumbnail, args.repeats)

            if shutil.which("sweep", path=env.get("PATH")):
                def sweep_scan():
                    scan = call("sweep.scan", f"path={sweep_project}")
                    if scan.get("protocolVersion") != "1" or not any(
                            Path(c.get("path", "")).name == "node_modules" for c in scan.get("candidates", [])):
                        raise ValueError(f"unexpected Sweep scan: {scan}")
                    call("sweep.discard", f"token={scan['token']}")
                sweep_scan()
                result["measurements"]["sweep_scan_complete"] = sample(sweep_scan, args.repeats)
                result["not_measured"].pop("Sweep scans")

            def search():
                completed = subprocess.run([str(binary), "--json", "search", "--direct", str(fixture), "entry-000000.txt"],
                                           env=env, capture_output=True, text=True, timeout=60, check=True)
                found = json.loads(completed.stdout)
                if found.get("partial") or found.get("truncated") or found.get("count") != 1:
                    raise ValueError(f"unexpected or incomplete search: {found}")
            search()
            result["measurements"]["search_direct_complete"] = sample(search, args.repeats)

            serial = 0
            def copy(source, expected_files, expected_bytes):
                nonlocal serial
                serial += 1
                dest = copies / str(serial)
                dest.mkdir()
                job = call("files.op.copy", f"paths={source}", f"dest={dest}").get("job", {})
                job_id = job.get("id")
                if not job_id:
                    raise ValueError("copy did not return a job id")
                deadline = time.monotonic() + 120
                while True:
                    jobs = call("files.op.jobs").get("jobs", [])
                    job = next((item for item in jobs if item.get("id") == job_id), None)
                    if not job:
                        raise ValueError(f"copy job disappeared: {job_id}")
                    if job.get("state") in ("done", "failed", "cancelled"):
                        break
                    if job.get("conflict") or job.get("failure") or time.monotonic() >= deadline:
                        raise RuntimeError(f"copy job did not complete: {job}")
                    time.sleep(0.01)
                if job.get("state") != "done" or job.get("cancelled") or job.get("skipped") or job.get("warnings"):
                    raise RuntimeError(f"copy failed or incomplete: {job}")
                target = dest / source.name
                if source.is_dir():
                    files = [p for p in target.rglob("*") if p.is_file()]
                    if len(files) != expected_files or sum(p.stat().st_size for p in files) != expected_bytes:
                        raise ValueError("small-file copy did not match expected count and size")
                elif not target.is_file() or target.stat().st_size != expected_bytes:
                    raise ValueError("large-file copy did not match expected size")

            large_bytes = args.large_mib * 1024 * 1024
            small_files = min(args.files, 1000)
            small_bytes = small_files * len("fjord copy benchmark\n")
            copy(large, 1, large_bytes)
            result["measurements"]["copy_large_complete"] = sample(lambda: copy(large, 1, large_bytes), args.repeats)
            copy(small, small_files, small_bytes)
            result["measurements"]["copy_small_complete"] = sample(lambda: copy(small, small_files, small_bytes), args.repeats)
            if args.gui_launcher:
                launcher = gui_launcher
                gui_env = env.copy()
                gui_env.pop("DFILES_SOCKET", None)
                gui_env["DFILES_QS_CHILD"] = "1"
                gui_env["WAYLAND_DISPLAY"] = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000"),
                                                           os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
                result["conditions"]["gui_observer"] = "Umbriel mapped visible window; isolated XDG/D-Bus; not first rendered frame"
                result["measurements"]["gui_window_visible"] = sample(lambda: gui_start(launcher, gui_env), args.repeats)
                result["not_measured"].pop("GUI startup")
        finally:
            daemon.terminate()
            try:
                daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait()
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
