#!/bin/bash
# Packs dist/sudoku/ into release archives in dist/release/ (run tools/build.sh first).
#   sudoku-appload-<version>-aarch64.tar.gz   (used by the Vellum package)
#   sudoku-appload-<version>-aarch64.zip      (manual install)
#   SHA512SUMS
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"
for f in manifest.json icon.png resources.rcc backend/entry; do
    [ -f "$HERE/dist/sudoku/$f" ] || { echo "missing dist/sudoku/$f (run tools/build.sh)"; exit 1; }
done
REL="$HERE/dist/release"
rm -rf "$REL" && mkdir -p "$REL"
BASE="sudoku-appload-$VERSION-aarch64"
# Archive layout: sudoku/<files>, so it unpacks straight into .../appload/.
(cd "$HERE/dist" && tar --owner=0 --group=0 --numeric-owner -czf "$REL/$BASE.tar.gz" sudoku)
if command -v zip >/dev/null 2>&1; then
    (cd "$HERE/dist" && zip -qr "$REL/$BASE.zip" sudoku)
else
    (cd "$HERE/dist" && python3 -c "import shutil,sys;shutil.make_archive(sys.argv[1],'zip','.','sudoku')" "$REL/$BASE")
fi
(cd "$REL" && sha512sum "$BASE".tar.gz "$BASE".zip > SHA512SUMS && cat SHA512SUMS)
