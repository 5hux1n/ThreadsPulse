#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d /tmp/tp-localization-test.XXXXXX)
trap 'rm -rf "$temp_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.app/Contents/Developer}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
python3 "$root/scripts/generate-localization.py" \
    --source "$root/resources/localization" --output "$root/.generated/TPLocalizationData.h"
python3 - "$root" "$temp_dir/source-tables.plist" <<'PY'
import hashlib
from pathlib import Path
import plistlib
import re
import runpy
import subprocess
import sys

root = Path(sys.argv[1])
parse_strings = runpy.run_path(str(root / 'scripts/generate-localization.py'))['parse_strings']
assert parse_strings('/* lead */ "key" /* between */ = "value"; // end', '<test>') == {'key': 'value'}
assert parse_strings(r'"quote\" slash\\ line\n" = "Unicode \u4e2d";', '<test>') == {'quote" slash\\ line\n': 'Unicode 中'}
for invalid in (
    '"a" = "b"; garbage', '"a" = "b"; "a" = "c";',
    r'"a" = "bad\q";', '"a" = "b"', '"a" = 12;', '/* unterminated',
):
    try:
        parse_strings(invalid, '<invalid>')
    except ValueError as error:
        assert '<invalid>:' in str(error), 'Parser errors must identify the source location'
    else:
        raise AssertionError(f'Unsupported or incomplete .strings accepted: {invalid}')
expected_hashes = {
    'en': 'd97ce5c9a81cfca7f3b8d7c5f2c324d86e323be03b01ee8952c9242271414d95',
    'ja': '647c2107f9e6109d6fbd1093e5a63241ed2238b306301af3493eac5e5436c4c3',
    'ko': '8f6de94d279896173016b71b04c155cb435fd4770c10eba71b59010ea419d8c1',
    'zh-Hans': '5015e82a4c6f98bcf6a81bd62830fb20e15fb810360bd7de1d81d86c81e394dc',
    'zh-Hant': 'cd3f5a6f6af12e38d03fb169bd835565ab2ae6179233311146c39a944f7f628b',
}
tables = {}
for code, expected_hash in expected_hashes.items():
    source = root / 'resources/localization' / f'{code}.lproj/Localizable.strings'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == expected_hash, f'{code}: source changed during migration'
    tables[code] = plistlib.loads(subprocess.check_output([
        '/usr/bin/plutil', '-convert', 'xml1', '-o', '-', str(source)
    ]))
    assert parse_strings(source.read_text(), source) == tables[code], f'{code}: Python/plutil mismatch'
header = root / '.generated/TPLocalizationData.h'
payload = bytes(int(value, 16) for value in re.findall(r'0x([0-9a-f]{2})', header.read_text()))
assert len(payload) == 66626
assert hashlib.sha256(payload).hexdigest() == '5440289a476c1afcb305eb160b35dc3907bedf141edbb48e34436fa3d18ba859', 'Payload changed when removing plutil dependency'
catalog = plistlib.loads(payload)
assert catalog['tables'] == tables, 'Embedded tables must match every source key and value'
assert catalog['developmentRegion'] == 'en'
assert catalog['localizations'] == ['en', 'zh-Hant', 'zh-Hans', 'ja', 'ko']
assert not list((root / 'layout').rglob('*.bundle')), 'No external localization bundle may be packaged'
before = header.stat().st_mtime_ns
subprocess.run([sys.executable, str(root / 'scripts/generate-localization.py'),
                '--source', str(root / 'resources/localization'), '--output', str(header)], check=True)
assert header.stat().st_mtime_ns == before, 'Unchanged translations must not trigger a rebuild'
Path(sys.argv[2]).write_bytes(plistlib.dumps(tables))
print(f'localization source preservation: PASS (5 x 346 entries; {len(payload)} embedded bytes)')
PY
xcrun --sdk macosx clang -fobjc-arc -fblocks -framework Foundation -I "$root" \
    "$root/TPLocalization.m" "$root/tests/localization.m" -o "$temp_dir/localization"
for pair in en:en zh-CN:zh-Hans zh-SG:zh-Hans zh-TW:zh-Hant zh-HK:zh-Hant zh-Hans:zh-Hans zh-Hant:zh-Hant ja:ja ko:ko fr:en; do
    language=${pair%%:*}
    table=${pair#*:}
    TP_TEST_SYSTEM_TABLE="$table" "$temp_dir/localization" "$temp_dir/source-tables.plist" -AppleLanguages "(\"$language\")"
done
