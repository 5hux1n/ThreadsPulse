#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
binary=$(mktemp /tmp/tp-music-test.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun clang -fobjc-arc -framework Foundation -I "$root" \
    "$root/TPMusicAttachment.m" "$root/tests/music-attachment.m" -o "$binary"
"$binary"
