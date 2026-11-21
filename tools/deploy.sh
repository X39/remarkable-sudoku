#!/bin/bash
# Copies dist/sudoku/ to the tablet over USB SSH (run tools/build.sh first).
#   RM_HOST (default 10.11.99.1)   RM_KEY (default ~/.ssh/id_ed25519)
# Afterwards reload AppLoad (or restart xochitl) so the new build is picked up.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${RM_HOST:-10.11.99.1}"
KEY="${RM_KEY:-$HOME/.ssh/id_ed25519}"
REMOTE="/home/root/xovi/exthome/appload/sudoku"
SSH=(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 "root@$HOST")
tar -C "$HERE/dist/sudoku" -cf - . | "${SSH[@]}" "rm -rf $REMOTE && mkdir -p $REMOTE && tar -C $REMOTE -xf -"
"${SSH[@]}" "chmod 755 $REMOTE/backend/entry; md5sum $REMOTE/resources.rcc"
md5sum "$HERE/dist/sudoku/resources.rcc"
