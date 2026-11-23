#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d /tmp/tp-pin-tab-test.XXXXXX)
trap 'rm -rf "$temp_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.app/Contents/Developer}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
python3 - "$root" "$temp_dir/pin-tab-bar.x" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / 'Tweak.x').read_text()
start = '%group LegacyPinTabBar\n'
assert source.count(start) == 1
group = start + source.split(start, 1)[1].split('// Suggestions are IGListKit sections', 1)[0]
assert group.count('%hook ') == 1
assert 'moveDownTabBarToOffset:(double)offset percentTransitioned:(double)percent' in group
assert 'setBarButtonAlpha:(double)alpha' in group
for forbidden in ['setHidden:', 'setTransform:', 'viewDidLayoutSubviews', 'viewWillLayoutSubviews', 'viewWillAppear:', 'viewDidAppear:', 'IGTabBar', 'TPIvarAddress']:
    assert forbidden not in group, f'Pinning must not override native visibility/layout: {forbidden}'
ctor = source.split('%ctor {', 1)[1]
assert 'class_getInstanceMethod(legacyTabRoot, @selector(moveDownTabBarToOffset:percentTransitioned:))' in ctor
assert 'class_getInstanceMethod(legacyTabRoot, @selector(setBarButtonAlpha:))' in ctor
fixture = (root / 'tests/pin-tab-bar.x').read_text()
fixture = fixture.replace('// PRODUCTION_PIN_HOOK', group + '\n%ctor { %init(LegacyPinTabBar); }')
Path(sys.argv[2]).write_text(fixture)
PY
"${THEOS:-/Users/manjunhong/theos}/bin/logos.pl" -c generator=internal "$temp_dir/pin-tab-bar.x" > "$temp_dir/pin-tab-bar.mm"
xcrun --sdk macosx clang++ -fobjc-arc -framework Foundation "$temp_dir/pin-tab-bar.mm" -o "$temp_dir/pin-tab-test"
"$temp_dir/pin-tab-test"
