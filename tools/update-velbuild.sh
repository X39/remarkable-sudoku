#!/bin/sh
# Sets pkgver and the sha512 in vellum/VELBUILD for a published GitHub release.
# Usage: tools/update-velbuild.sh <version>      e.g. tools/update-velbuild.sh 0.1.0
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:?usage: tools/update-velbuild.sh <version>}"
NAME="sudoku-appload-$VER-aarch64.tar.gz"
URL="https://github.com/X39/remarkable-sudoku/releases/download/v$VER/$NAME"
SUM="$(curl -fsSL "$URL" | sha512sum | cut -d' ' -f1)"
[ "${#SUM}" -eq 128 ] || { echo "could not hash $URL"; exit 1; }
F="$HERE/vellum/VELBUILD"
sed -i "s/^pkgver=.*/pkgver=$VER/; s/^pkgrel=.*/pkgrel=0/; s/^[0-9a-f]\{128\}  sudoku-appload-.*/$SUM  $NAME/" "$F"
echo "VELBUILD updated for v$VER"
