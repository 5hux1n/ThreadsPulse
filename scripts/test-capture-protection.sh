#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d /tmp/tp-capture-test.XXXXXX)
trap 'rm -rf "$temp_dir"' EXIT
if [ -z "$(printenv DEVELOPER_DIR || true)" ]; then export DEVELOPER_DIR=/Applications/Xcode-16.4.app/Contents/Developer; fi
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
python3 - "$root/TPUI.m" "$root/tests/capture-protection.m" "$temp_dir/capture-protection-test.m" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
fixture = Path(sys.argv[2]).read_text()
start = 'static UIView *TPFindSecureCanvas('
end = 'static __weak UIView *sTPMenuAnchor;'
marker = '// INSERT_PRODUCTION_CAPTURE_CODE_HERE'
if source.count(start) != 1 or source.count(end) != 1 or fixture.count(marker) != 1:
    raise SystemExit('Capture test extraction markers changed')
production = start + source.split(start, 1)[1].split(end, 1)[0]
Path(sys.argv[3]).write_text(fixture.replace(marker, production))
PY
xcrun --sdk macosx clang -fobjc-arc -framework Foundation -framework QuartzCore -framework CoreGraphics \
    "$temp_dir/capture-protection-test.m" -o "$temp_dir/capture-protection-test"
"$temp_dir/capture-protection-test"
