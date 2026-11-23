#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d /tmp/tp-ad-delivery-test.XXXXXX)
trap 'rm -rf "$temp_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.app/Contents/Developer}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
python3 - "$root" "$temp_dir/ad-delivery.x" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / 'Tweak.x').read_text()
start = '%hook IGAdInsertionHandler\n'
assert source.count(start) == 1, 'Expected one shared ad delivery hook'
hook = start + source.split(start, 1)[1].split('%end', 1)[0] + '%end'
fixture = (root / 'tests/ad-delivery.x').read_text()
fixture = fixture.replace('// PRODUCTION_AD_HOOK', '%group TestAds\n' + hook + '\n%end\n%ctor { %init(TestAds); }')
Path(sys.argv[2]).write_text(fixture)
PY
"${THEOS:-/Users/manjunhong/theos}/bin/logos.pl" -c generator=internal "$temp_dir/ad-delivery.x" > "$temp_dir/ad-delivery.mm"
xcrun --sdk macosx clang++ -fobjc-arc -framework Foundation "$temp_dir/ad-delivery.mm" -o "$temp_dir/ad-delivery-test"
"$temp_dir/ad-delivery-test"
