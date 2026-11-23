#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d /tmp/threadspulse-pack.XXXXXX)
export LC_ALL=C
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.app/Contents/Developer}"
rsync -a --exclude .git --exclude .theos --exclude build --exclude packages --exclude dist "$root/" "$work/"
mkdir -p "$root/dist"
for scheme in rootless roothide; do
    if [ "$scheme" = rootless ]; then
        toolchain="${THEOS_ROOTLESS:-/Users/manjunhong/theos}"
        arch=arm64
    else
        toolchain="${THEOS_ROOTHIDE:-/Users/manjunhong/theos-roothide}"
        arch=arm64e
    fi
    (cd "$work" && THEOS="$toolchain" make clean && THEOS="$toolchain" make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$scheme" THEOS_PACKAGE_DIR="$work/build/$scheme")
    deb=("$work/build/$scheme/"*.deb)
    version=$(dpkg-deb -f "${deb[0]}" Version)
    test "$(dpkg-deb -f "${deb[0]}" Architecture)" = "iphoneos-$arch"
    test "${#deb[@]}" = 1
    cp "${deb[0]}" "$root/dist/ThreadsPulse_${version}_${arch}.deb"
done
printf 'Build files and logs: %s\n' "$work"
