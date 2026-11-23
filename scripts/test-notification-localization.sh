#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d /tmp/tp-notification-test.XXXXXX)
trap 'rm -rf "$temp_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.app/Contents/Developer}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang -fobjc-arc -DTP_NOTIFICATION_PREFS_TESTING=1 -framework Foundation \
    "$root/tests/notification-prefs.m" "$root/TPNotificationPrefs.m" "$root/TPPrefs.m" -o "$temp_dir/prefs"
"$temp_dir/prefs"
python3 - "$root" "$temp_dir/notification-localization.x" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / 'ThreadsPulseNotifications.x').read_text()
start = '@interface TPNotificationRecovery'
assert source.count(start) == 1, 'Exercise the complete production recovery state and notification hook'
production = start + source.split(start, 1)[1]
assert '#import' not in production, 'The fixture supplies platform stubs and the preferences reader'
assert production.count('%hook ') == 1 and production.count('%group ') == 1
assert production.count('%ctor {') == 1, 'Exercise the actual production constructor'
assert 'NSLocale.preferredLanguages' in production
assert 'TPLocalizedFollowingSystem' not in production and 'TPBundle(' not in production
fixture = (root / 'tests/notification-localization.x').read_text()
fixture = fixture.replace('// PRODUCTION_NOTIFICATION_HOOK', production)
Path(sys.argv[2]).write_text(fixture)
PY
"${THEOS:-/Users/manjunhong/theos}/bin/logos.pl" -c generator=internal "$temp_dir/notification-localization.x" > "$temp_dir/notification-localization.mm"
xcrun --sdk macosx clang++ -fobjc-arc -Werror=arc-retain-cycles -include "$root/TPVersion.h" -framework Foundation "$temp_dir/notification-localization.mm" -o "$temp_dir/BarcelonaNotificationExtension"
for language in zh-CN zh-TW zh-HK zh-Hans zh-Hant en ja ko fr; do
    if ! TP_TEST_LANGUAGE="$language" "$temp_dir/BarcelonaNotificationExtension" -AppleLanguages "(\"$language\")" 2>"$temp_dir/$language.log"; then
        cat "$temp_dir/$language.log" >&2
        exit 1
    fi
done
cp "$temp_dir/BarcelonaNotificationExtension" "$temp_dir/Threads"
if ! TP_TEST_LANGUAGE=zh-CN TP_TEST_EXPECT_NO_HOOK=1 "$temp_dir/Threads" -AppleLanguages '("zh-CN")' 2>"$temp_dir/main-app.log"; then
    cat "$temp_dir/main-app.log" >&2
    exit 1
fi
