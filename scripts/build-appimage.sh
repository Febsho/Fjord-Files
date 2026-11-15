#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=${APPIMAGE_WORK_DIR:-"$ROOT/.appimage-work"}
APPDIR="$WORK_DIR/AppDir"
APP_ID=io.github.febsho.fjordfiles
APP_NAME=Fjord-Files
ARCH=$(uname -m)
OUTPUT=${1:-"$ROOT/dist/${APP_NAME}-${ARCH}.AppImage"}
if [[ -n "${APPIMAGETOOL:-}" ]]; then
  APPIMAGETOOL_PINNED=0
else
  APPIMAGETOOL="$WORK_DIR/tools/appimagetool-${ARCH}.AppImage"
  APPIMAGETOOL_PINNED=1
fi
RUNTIME_FILE=${APPIMAGE_RUNTIME_FILE:-"$WORK_DIR/tools/runtime-${ARCH}"}

if [[ "$ARCH" != x86_64 ]]; then
  echo "AppImage packaging currently supports x86_64 only (got $ARCH)." >&2
  exit 2
fi
for command in make go quickshell rsvg-convert; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done
command -v curl >/dev/null || { echo "Missing required command: curl" >&2; exit 2; }
mkdir -p "$(dirname -- "$APPIMAGETOOL")" "$(dirname -- "$RUNTIME_FILE")"
download_verified() {
  local destination=$1 url=$2 expected=$3 temporary
  if [[ ! -f "$destination" ]]; then
    temporary=$(mktemp "${destination}.download.XXXXXX")
    if ! curl -fL --retry 3 --retry-delay 1 "$url" -o "$temporary"; then
      rm -f -- "$temporary"
      return 1
    fi
    mv -f -- "$temporary" "$destination"
  fi
  echo "$expected  $destination" | sha256sum -c - >/dev/null || {
    echo "Checksum mismatch for $destination; remove it and retry." >&2
    return 1
  }
}
if (( APPIMAGETOOL_PINNED )); then
  download_verified "$APPIMAGETOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage" \
    e8c1169c4af66c3184d7ee110713d4be04befe671fa358e2c1591ee840553b03
fi
[[ -x "$APPIMAGETOOL" ]] || { echo "Missing executable appimagetool: $APPIMAGETOOL" >&2; exit 2; }
download_verified "$RUNTIME_FILE" \
  "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-${ARCH}" \
  617aa77314d57c8b8e4fae9c3f0b35af7b30d5529cb69e98f64f92510ed98a46
[[ -d /usr/lib/qt6/qml && -d /usr/lib/qt6/plugins ]] || {
  echo "Qt 6 QML and plugin runtime must be installed under /usr/lib/qt6." >&2
  exit 2
}
[[ -f /usr/lib/libQt6Pdf.so.6 ]] || { echo "Qt 6 PDF runtime is required." >&2; exit 2; }

mkdir -p "$WORK_DIR" "$(dirname -- "$OUTPUT")"
STAGE=$(mktemp -d "$WORK_DIR/AppDir.new.XXXXXX")
TEMP_OUTPUT=$(mktemp "$(dirname -- "$OUTPUT")/.${APP_NAME}.XXXXXX.AppImage")
cleanup() { rm -rf -- "$STAGE"; rm -f -- "$TEMP_OUTPUT"; }
trap cleanup EXIT

make -C "$ROOT/core" build
make -C "$ROOT/core" sync-shell

mkdir -p "$STAGE/usr/bin" "$STAGE/usr/lib" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/metainfo" "$STAGE/usr/share/icons/hicolor/scalable/apps" \
  "$STAGE/usr/share/fjord-files" "$STAGE/usr/share/licenses/fjord-files"
install -m 755 "$ROOT/core/bin/dfiles" "$STAGE/usr/bin/fjord-files-daemon"
install -m 755 "$(command -v quickshell)" "$STAGE/usr/bin/quickshell-real"
cp -a /usr/lib/qt6 "$STAGE/usr/lib/"
for library in /usr/lib/libQt6Pdf.so.6 /usr/lib/libQt6PdfQuick.so.6 /usr/lib/libQt6PdfWidgets.so.6; do
  [[ ! -e "$library" ]] || cp -L --preserve=mode,timestamps "$library" "$STAGE/usr/lib/$(basename -- "$library")"
done

cat > "$STAGE/usr/bin/fjord-files" <<'EOF'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export DFILES_QS_CHILD=1
export PATH="$HERE/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QML2_IMPORT_PATH="$HERE/usr/lib/qt6/qml${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
export QT_PLUGIN_PATH="$HERE/usr/lib/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QT_QPA_PLATFORM_PLUGIN_PATH="$HERE/usr/lib/qt6/plugins/platforms"
exec "$HERE/usr/bin/fjord-files-daemon" "$@"
EOF
cat > "$STAGE/usr/bin/quickshell" <<'EOF'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$HERE/usr/bin/quickshell-real" --path "$HERE/usr/share/fjord-files/quickshell" "$@"
EOF
chmod 755 "$STAGE/usr/bin/fjord-files" "$STAGE/usr/bin/quickshell"
cp -a "$ROOT/quickshell/." "$STAGE/usr/share/fjord-files/quickshell/"
install -m 644 "$ROOT/assets/$APP_ID.desktop" "$STAGE/$APP_ID.desktop"
install -m 644 "$ROOT/assets/$APP_ID.desktop" "$STAGE/usr/share/applications/$APP_ID.desktop"
install -m 644 "$ROOT/assets/$APP_ID.metainfo.xml" "$STAGE/usr/share/metainfo/$APP_ID.appdata.xml"
install -m 644 "$ROOT/assets/$APP_ID.svg" "$STAGE/$APP_ID.svg"
install -m 644 "$ROOT/assets/$APP_ID.svg" "$STAGE/usr/share/icons/hicolor/scalable/apps/$APP_ID.svg"
rsvg-convert -w 512 -h 512 "$ROOT/assets/$APP_ID.svg" -o "$STAGE/$APP_ID.png"
cp -a "$ROOT/assets/licenses/." "$STAGE/usr/share/licenses/fjord-files/"
install -m 644 "$ROOT/LICENSE" "$STAGE/usr/share/licenses/fjord-files/LICENSE"

cat > "$STAGE/AppRun" <<'EOF'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$HERE/usr/bin/fjord-files" "$@"
EOF
chmod 755 "$STAGE/AppRun"

# Bundle non-glibc shared libraries needed by the shipped Qt/QML modules and
# QuickShell. Glibc and the Wayland/compositor stack remain host dependencies.
python3 - "$STAGE" <<'PY'
import os, re, shutil, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])
libdir = root / "usr/lib"
seen = set()
system = re.compile(r"^lib(c|m|pthread|dl|rt|resolv|nss_[^.]*)\.so|^ld-linux")
pending = [p for p in (root / "usr/bin").glob("*") if p.is_file() and p.name != "quickshell"]
pending += [p for p in libdir.glob("libQt6Pdf*.so*") if p.is_file()]
while pending:
    binary = pending.pop()
    try:
        result = subprocess.run(["ldd", str(binary)], text=True, capture_output=True, check=False)
    except OSError as exc:
        raise SystemExit(f"Cannot inspect shared libraries for {binary}: {exc}")
    for line in result.stdout.splitlines():
        match = re.search(r"=>\s+(/\S+)", line)
        if not match:
            continue
        source = Path(match.group(1))
        name = source.name
        if name in seen or system.match(name) or not source.exists():
            continue
        seen.add(name)
        target = libdir / name
        if not target.exists():
            shutil.copy2(source, target)
            pending.append(target)
PY

chmod -R a+rX "$STAGE"
"$APPIMAGETOOL" --appimage-extract-and-run "$STAGE" "$TEMP_OUTPUT" --runtime-file "$RUNTIME_FILE"
chmod 755 "$TEMP_OUTPUT"
"$TEMP_OUTPUT" --version >/dev/null
rm -rf -- "$APPDIR"
mv -T -- "$STAGE" "$APPDIR"
mv -f -- "$TEMP_OUTPUT" "$OUTPUT"
trap - EXIT
rm -rf -- "$STAGE"
sha256sum "$OUTPUT" | tee "$OUTPUT.sha256"
echo "Built $OUTPUT"
