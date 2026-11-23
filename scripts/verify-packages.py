#!/usr/bin/env python3
"""Validate DEB layout, iOS target, architecture and statically linked codecs."""
from pathlib import Path
import hashlib
import struct
import sys
import plistlib
import re
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent

def run(*args):
    return subprocess.check_output(args, text=True)

version = next(line.split(':', 1)[1].strip() for line in (root / 'control').read_text().splitlines()
               if line.startswith('Version:'))
with tempfile.TemporaryDirectory(prefix='tp-catalog-') as temp:
    header = Path(temp) / 'TPLocalizationData.h'
    subprocess.run([sys.executable, str(root / 'scripts/generate-localization.py'),
                    '--source', str(root / 'resources/localization'), '--output', str(header)], check=True)
    catalog = bytes.fromhex(' '.join(re.findall(r'0x([0-9a-f]{2})', header.read_text())))

for arch in ('arm64', 'arm64e'):
    deb = root / 'dist' / f'ThreadsPulse_{version}_{arch}.deb'
    assert run('dpkg-deb', '-f', str(deb), 'Architecture').strip() == f'iphoneos-{arch}'
    expected_name = 'ThreadsPulse' + (' (Roothide)' if arch == 'arm64e' else '')
    assert run('dpkg-deb', '-f', str(deb), 'Name').strip() == expected_name
    expected_id = 'com.h4x.threadspulse' + ('.roothide' if arch == 'arm64e' else '')
    assert run('dpkg-deb', '-f', str(deb), 'Package').strip() == expected_id
    assert run('dpkg-deb', '-f', str(deb), 'Version').strip() == version
    assert not run('dpkg-deb', '-f', str(deb), 'Depends').strip()
    with tempfile.TemporaryDirectory(prefix='tp-verify-') as temp:
        subprocess.run(['dpkg-deb', '-x', str(deb), temp], check=True)
        base = Path(temp) / ('var/jb' if arch == 'arm64' else '')
        dylib = base / 'Library/MobileSubstrate/DynamicLibraries/ThreadsPulse.dylib'
        assert dylib.is_file()
        assert run('lipo', '-archs', str(dylib)).strip() == arch
        commands = run('otool', '-l', str(dylib))
        assert re.search(r'minos\s+15\.0', commands)
        if arch == 'arm64e':
            assert '@loader_path/.jbroot/Library/Frameworks' in commands
            assert '@loader_path/.jbroot/usr/lib' in commands
            assert not (Path(temp) / 'var/jb').exists()
        symbols = run('nm', '-g', str(dylib))
        for name in ('_vpx_codec_vp9_dx', '_vpx_codec_decode', '_dav1d_open', '_dav1d_send_data'):
            assert re.search(r'^[0-9a-f]+ T ' + re.escape(name) + r'$', symbols, re.M), name
            assert not re.search(r'\bU ' + re.escape(name) + r'$', symbols, re.M)
        assert not re.search(r'\bU _MSHook', symbols)
        # Theos uses ldid jailbreak signatures; verify their embedded page hashes.
        binary = dylib.read_bytes()
        offset = 32
        signature = None
        for _ in range(struct.unpack_from('<I', binary, 16)[0]):
            command, size = struct.unpack_from('<II', binary, offset)
            if command == 0x1d:
                location, length = struct.unpack_from('<II', binary, offset + 8)
                signature = binary[location:location + length]
            offset += size
        assert signature is not None
        assert struct.unpack_from('>I', signature)[0] == 0xfade0cc0
        verified = 0
        for index in range(struct.unpack_from('>I', signature, 8)[0]):
            _, directory_offset = struct.unpack_from('>II', signature, 12 + 8 * index)
            directory = signature[directory_offset:]
            if struct.unpack_from('>I', directory)[0] != 0xfade0c02:
                continue
            _, length, _, _, hashes, _, _, count, limit = struct.unpack_from('>9I', directory)
            hash_size, hash_type, _, page_exp = struct.unpack_from('>4B', directory, 36)
            assert hash_type in (1, 2, 3)
            algorithm = 'sha1' if hash_type == 1 else 'sha256'
            page_size = 1 << page_exp
            assert count == (limit + page_size - 1) // page_size
            assert hashes + count * hash_size <= length
            for index in range(count):
                page = binary[index * page_size:min((index + 1) * page_size, limit)]
                digest = hashlib.new(algorithm, page).digest()[:hash_size]
                assert digest == directory[hashes + index * hash_size:hashes + (index + 1) * hash_size]
            verified += 1
        assert verified > 0
        assert list(Path(temp).rglob('*.dylib')) == [dylib]
        assert not list(Path(temp).rglob('ThreadsPulse.bundle'))
        assert version.encode() + b'\0' in binary
        for marker in (
            b'_TtC21BCNFeedNestedPostCell34BCNFeedDeletedQuotedAttachmentCell',
            b'text_app_music_info',
            b'moveDownTabBarToOffset:percentTransitioned:',
            b'setBarButtonAlpha:',
            b'fetchRootAppWithObjectSet:appID:params:purpose:cacheTTL:successHandler:errorHandler:callbackQueue:',
        ):
            assert marker + b'\0' in binary, marker
        assert catalog in binary
        filter_file = dylib.with_suffix('.plist')
        raw = run('plutil', '-convert', 'xml1', '-o', '-', str(filter_file))
        assert plistlib.loads(raw.encode())['Filter']['Executables'] == ['Threads', 'BarcelonaNotificationExtension']
    print(f'{deb.name}: architecture, iOS 15, layout, version, codecs, compatibility entry points, embedded languages, signature hashes and filter passed')
