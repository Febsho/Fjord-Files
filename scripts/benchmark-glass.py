#!/usr/bin/env python3
"""Compare Fjord's glass surface with plain Qt Quick surfaces on the current display."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
shell_dir = repo / "quickshell"
benchmark_qml = shell_dir / "benchmarks" / "glass.qml"
result_pattern = re.compile(r"FJORD_GLASS_BENCHMARK (\{.*\})")


def run_case(qs, harness, mode, warmup, seconds):
    with tempfile.TemporaryDirectory(prefix="fjord-glass-xdg-") as xdg:
        env = os.environ.copy()
        env.update({
            "FJORD_GLASS_MODE": mode,
            "FJORD_GLASS_WARMUP": str(warmup),
            "FJORD_GLASS_SECONDS": str(seconds),
            "XDG_CONFIG_HOME": str(Path(xdg) / "config"),
            "XDG_CACHE_HOME": str(Path(xdg) / "cache"),
            "XDG_DATA_HOME": str(Path(xdg) / "data"),
            "XDG_STATE_HOME": str(Path(xdg) / "state"),
            "QSG_INFO": "1",
        })
        process = subprocess.run(
            [qs, "-p", str(harness)],
            cwd=repo,
            env=env,
            capture_output=True,
            text=True,
            timeout=warmup + seconds + 30,
            check=False,
        )
    output = process.stdout + process.stderr
    match = result_pattern.search(output)
    if process.returncode != 0 or not match:
        raise RuntimeError(f"{mode} run failed (exit {process.returncode}):\n{output[-5000:]}")
    result = json.loads(match.group(1))
    result["rendererInfo"] = [
        line.strip() for line in output.splitlines()
        if re.search(r"Graphics API:|RHI Backend:|Using QRhi|Device:|Adapter:", line, re.IGNORECASE)
    ]
    return result


def command_output(command):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=2, check=False).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=8, help="measured time per run")
    parser.add_argument("--warmup", type=float, default=2, help="discarded startup time per run")
    parser.add_argument("--repeats", type=int, default=3, help="runs for each mode")
    parser.add_argument("--output", type=Path, help="optional JSON result path")
    args = parser.parse_args()
    if args.seconds <= 0 or args.warmup < 0 or args.repeats < 1:
        parser.error("seconds must be positive, warmup non-negative, and repeats at least one")

    qs = os.environ.get("QS") or shutil.which("qs")
    if not qs:
        raise SystemExit("Quickshell is required; set QS to its path")
    if not os.environ.get("WAYLAND_DISPLAY") and not os.environ.get("DISPLAY"):
        raise SystemExit("Run this benchmark inside a graphical desktop session")

    results = {"plain": [], "glass": [], "refraction": []}
    with tempfile.TemporaryDirectory(prefix="fjord-glass-bench-") as tmp:
        harness = Path(tmp) / "shell"
        harness.mkdir()
        for entry in shell_dir.iterdir():
            if entry.name in ("shell.qml", "scripts", "tests", ".qmlls.ini"):
                continue
            (harness / entry.name).symlink_to(entry)
        shutil.copy(benchmark_qml, harness / "shell.qml")

        for repeat in range(args.repeats):
            modes = ("plain", "glass", "refraction") if repeat % 2 == 0 else ("refraction", "glass", "plain")
            for mode in modes:
                result = run_case(qs, harness, mode, args.warmup, args.seconds)
                results[mode].append(result)
                print(f"{mode:5} {result['fps']:.1f} fps ({result['frames']} frames)", flush=True)

    medians = {mode: statistics.median(run["fps"] for run in runs) for mode, runs in results.items()}
    change = (medians["glass"] / medians["plain"] - 1) * 100 if medians["plain"] else 0
    refraction_change = (medians["refraction"] / medians["plain"] - 1) * 100 if medians["plain"] else 0
    report = {
        "repeats": args.repeats,
        "warmupSeconds": args.warmup,
        "measureSeconds": args.seconds,
        "medianFps": medians,
        "glassFpsChangePercent": round(change, 1),
        "refractionFpsChangePercent": round(refraction_change, 1),
        "runs": results,
        "conditions": {
            "display": os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"),
            "desktop": os.environ.get("XDG_CURRENT_DESKTOP", ""),
            "qtQuickVersion": command_output(["pkg-config", "--modversion", "Qt6Quick"]) or "unknown",
            "gpu": command_output(["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"]) or "not reported",
            "notes": "plain/glass modes render 100 static cards; refraction mode renders one app-owned-texture strip; FrameAnimation frame cadence; compositor blur remains compositor-controlled."
        }
    }
    print(json.dumps(report, indent=2))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
