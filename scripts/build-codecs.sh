#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d /tmp/threadspulse-codecs.XXXXXX)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.app/Contents/Developer}"
export LC_ALL=C
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
cc=$(xcrun --find clang)
git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git "$work/vpx"
git -C "$work/vpx" fetch --depth 1 origin 6f4dbb1bc6803cbcdb7f54bd1c11a6228b717705
git -C "$work/vpx" checkout --detach FETCH_HEAD
git clone --depth 1 https://github.com/videolan/dav1d.git "$work/dav"
git -C "$work/dav" fetch --depth 1 origin 39834d7f71c85a9c555f2ddd7a7add6d671750de
git -C "$work/dav" checkout --detach FETCH_HEAD
python3 - "$work/vpx/build/make/configure.sh" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
assert 'IOS_VERSION_MIN="7.0"' in s and '-arch ${tgt_isa}' in s
p.write_text(s.replace('IOS_VERSION_MIN="7.0"', 'IOS_VERSION_MIN="15.0"').replace('-arch ${tgt_isa}', '-arch ${TP_DECODER_ARCH}'))
PY
for arch in arm64 arm64e; do
    mkdir -p "$work/vpx-$arch"
    (cd "$work/vpx-$arch" && TP_DECODER_ARCH="$arch" "$work/vpx/configure" --target=arm64-darwin-gcc --disable-vp8 --disable-vp9-encoder --enable-vp9-highbitdepth --enable-multithread --disable-runtime-cpu-detect --disable-neon-dotprod --disable-neon-i8mm --disable-sve --disable-sve2 --disable-examples --disable-tools --disable-docs --disable-unit-tests && make -j4)
    cat > "$work/dav-$arch.ini" <<EOF
[binaries]
c = '$cc'
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = '$arch'
endian = 'little'
[built-in options]
c_args = ['-target', '$arch-apple-ios15.0', '-isysroot', '$sdk']
c_link_args = ['-target', '$arch-apple-ios15.0', '-isysroot', '$sdk']
EOF
    "${UV:-uv}" tool run --from meson==1.9.1 meson setup "$work/dav-$arch" "$work/dav" --cross-file "$work/dav-$arch.ini" --default-library static --buildtype release -Denable_tools=false -Denable_tests=false -Denable_examples=false
    ninja -C "$work/dav-$arch"
    lipo "$work/vpx-$arch/libvpx.a" -verify_arch "$arch"
    lipo "$work/dav-$arch/src/libdav1d.a" -verify_arch "$arch"
done
lipo -create "$work/vpx-arm64/libvpx.a" "$work/vpx-arm64e/libvpx.a" -output "$work/libvpx.a"
lipo -create "$work/dav-arm64/src/libdav1d.a" "$work/dav-arm64e/src/libdav1d.a" -output "$work/libdav1d.a"
cp "$work/libvpx.a" "$root/vendor/libvpx/lib/"
cp "$work/libdav1d.a" "$root/vendor/dav1d/lib/"
printf 'Codec source and build files: %s\n' "$work"
