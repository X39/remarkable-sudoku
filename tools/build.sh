#!/bin/bash
# Builds the AppLoad app into dist/sudoku/:  manifest.json, icon.png, resources.rcc, backend/entry
#   resources.rcc : Qt resource bundle compiled from application.qrc (needs `rcc`)
#   backend/entry : Rust pen-eraser helper for aarch64 (reMarkable Paper Pro), static musl
# Environment: RCC=<path to rcc> to override the lookup (rcc, pyside6-rcc, tools/.venv).
#              SKIP_BACKEND=1 to skip the Rust build (UI-only iteration).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/dist/sudoku"
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"

find_rcc() {
    if [ -n "${RCC:-}" ]; then echo "$RCC"; return; fi
    local c
    for c in rcc pyside6-rcc \
             "$HERE/tools/.venv/bin/pyside6-rcc" \
             "$HERE/tools/.venv/Lib/site-packages/PySide6/rcc.exe" \
             /usr/lib/qt6/rcc /usr/lib/qt6/libexec/rcc; do
        if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then echo "$c"; return; fi
    done
    echo "rcc not found: install Qt's rcc, or 'pip install PySide6', or set RCC=" >&2
    exit 1
}
RCC_BIN="$(find_rcc)"

rm -rf "$OUT" && mkdir -p "$OUT"
cp "$HERE/manifest.json" "$HERE/icon.png" "$OUT/"

if [ -z "${SKIP_BACKEND:-}" ]; then
    (cd "$HERE/backend" && cargo build --release --locked)
    mkdir -p "$OUT/backend"
    cp "$HERE/backend/target/aarch64-unknown-linux-musl/release/entry" "$OUT/backend/entry"
fi

# The stamp is logged at startup ("DBG build ...") so a stale build can be spotted in the journal.
SHA="$(git -C "$HERE" rev-parse --short HEAD 2>/dev/null || echo nogit)"
echo "v$VERSION $SHA $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$HERE/ui/build-stamp.txt"
(cd "$HERE" && "$RCC_BIN" --binary -o "$OUT/resources.rcc" application.qrc)
ls -l "$OUT" "$OUT/backend" 2>/dev/null || ls -l "$OUT"
