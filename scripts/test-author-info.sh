#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d /tmp/tp-author-test.XXXXXX)
trap 'rm -rf "$temp_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.app/Contents/Developer}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
python3 - "$root/TPAuthorInfo.m" "$temp_dir/author-info-test.m" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()

def section(start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise SystemExit(f"Author test extraction markers changed: {start} / {end}")
    return start + source.split(start, 1)[1].split(end, 1)[0]

prefix = '''#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
// Only needed to compile the production harvester's UIKit exclusion checks on macOS.
@interface UIResponder : NSObject @end
@implementation UIResponder @end
@interface UIImage : NSObject @end
@implementation UIImage @end
'''
body = section("static BOOL TPHasAuthorDetails(", "static void TPLoadCache(")
body += section("static BOOL TPIsNewAccountAtDate(", "+ (BOOL)isNewAccount:")
body += section("static BOOL TPSkipClass(", "static BOOL TPLooksRateLimited(")
Path(sys.argv[2]).write_text(prefix + body + '\n#include "author-info.m"\n')
PY
xcrun --sdk macosx clang -fobjc-arc -Wno-incompatible-pointer-types -framework Foundation -framework QuartzCore \
    -I "$root/tests" "$temp_dir/author-info-test.m" -o "$temp_dir/author-info-test"
"$temp_dir/author-info-test"
