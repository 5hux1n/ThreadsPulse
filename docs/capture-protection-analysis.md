# Capture protection repair

The upstream implementation created a zero-sized secure text field, inspected only its immediate
children, then detached the canvas without retaining the field. A missing canvas fell back to
ordinary drawing. This same implementation was present in the local migration trees.

The shared container now creates and lays out a nonzero-sized secure field, searches a bounded
subtree, and keeps the field/canvas native hierarchy alive. Canvas geometry is converted from
the host's bounds after field layout. The outer host retains its touch handling and accessibility.
Only visual content enters the canvas; UIKit-owned button image views are not moved.

The common helper covers circular download controls, download capsules/cards, the chat eye,
the slide-to-lock control, and the fixed-English Pulse entry. Existing controls also respond to
the capture setting notification. Chat eye images, colors, read-state behavior, and original
messages are preserved. Author information text and native settings controls are outside scope.

The test script scripts/test-capture-protection.sh extracts the production implementation and
checks ownership, nested geometry, content replacement, setting changes, resizing, and fallback
using local UIKit stubs. It does not verify the iOS compositor or real screenshots/recordings.
A device must still verify captured output, visible button geometry, taps, long presses, and
transitions. If UIKit has no matching secure canvas, content continues to draw normally.
