#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/quickshell/shaders/glass-refraction.frag"
OUTPUT="$ROOT/quickshell/shaders/glass-refraction.frag.qsb"

if [[ -n "${QSB:-}" ]]; then
  QSB_COMMAND=$QSB
elif command -v qsb >/dev/null 2>&1; then
  QSB_COMMAND=$(command -v qsb)
elif [[ -x /usr/lib/qt6/bin/qsb ]]; then
  QSB_COMMAND=/usr/lib/qt6/bin/qsb
else
  echo "Qt Shader Tools (qsb) is required to compile the glass shader." >&2
  exit 2
fi

"$QSB_COMMAND" --qt6 --qsbversion 64 -o "$OUTPUT" "$SOURCE"
