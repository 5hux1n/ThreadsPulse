#!/usr/bin/env python3
"""Inspect live `text_app_music_info` payloads on a jailbroken iPhone.

The tweak can only render a play button when the payload carries a playable
audio DASH manifest. This probe prints the payload shape (and the tweak's own
diagnostics) so a server-side change is identified in one run instead of by
guessing from a missing button.

Usage:
    python3 scripts/probe-music-payload.py [--scroll] [--seconds 40]
                                           [--device UDID] [--out samples.jsonl]

Requires frida + frida-tools on the Mac. The ObjC bridge is not bundled in
Frida 17, so it is prepended from frida_tools (see ~/.codex/environment.md).
"""

import argparse
import json
import time
from pathlib import Path

import frida
import frida_tools

BUNDLE_ID = "com.burbn.barcelona"

PRELUDE = r"""
function safe(f, d) { try { return f(); } catch (e) { return d === undefined ? ('ERR:' + e) : d; } }
function ser(obj) {
  try {
    const data = ObjC.classes.NSJSONSerialization.dataWithJSONObject_options_error_(obj, 0, NULL);
    if (data.isNull()) return null;
    const str = ObjC.classes.NSString.alloc().initWithData_encoding_(data, 4);
    return str ? str.toString() : null;
  } catch (e) { return null; }
}
const seen = {};
function reportSource(source, json) {
  if (!json || json.indexOf('text_app_music_info') < 0 || seen[json]) return;
  seen[json] = 1;
  let diagnostics = null;
  const TPMusicAttachment = ObjC.classes.TPMusicAttachment;
  const method = TPMusicAttachment && TPMusicAttachment['+ diagnosticsForDictionary:'];
  if (method) {
    diagnostics = safe(() => {
      const data = ObjC.classes.NSString.stringWithString_(json).dataUsingEncoding_(4);
      const info = ObjC.classes.NSJSONSerialization.JSONObjectWithData_options_error_(data, 0, NULL);
      const result = TPMusicAttachment.diagnosticsForDictionary_(info);
      return new ObjC.Object(result).description().toString();
    });
  } else {
    diagnostics = 'n/a (installed tweak predates diagnosticsForDictionary:)';
  }
  send({ source: source, json: json, diagnostics: diagnostics });
}
"""

HOOKS = r"""
const IGMedia = ObjC.classes.IGMedia;
if (IGMedia) {
  Interceptor.attach(IGMedia['- updateWithDictionary:'].implementation, {
    onEnter(args) { reportSource('update', ser(new ObjC.Object(args[2]))); }
  });
}
const TPMusicAttachment = ObjC.classes.TPMusicAttachment;
if (TPMusicAttachment) {
  Interceptor.attach(TPMusicAttachment['+ attachmentWithDictionary:'].implementation, {
    onEnter(args) { reportSource('tweak', ser(new ObjC.Object(args[2]))); }
  });
}
"""

SCROLL = r"""
let coll = null, offsetY = 0;
function findFeed(view, depth) {
  if (!view || depth > 12) return null;
  if (view.$className.indexOf('BCNFeedCollectionView') >= 0) return view;
  const subs = safe(() => view.subviews(), null);
  if (!subs) return null;
  for (let i = 0; i < subs.count(); i++) {
    const hit = findFeed(ObjC.Object(subs.objectAtIndex_(i)), depth + 1);
    if (hit) return hit;
  }
  return null;
}
setInterval(function () {
  if (!coll) {
    const window = ObjC.classes.UIApplication.sharedApplication().keyWindow();
    coll = window ? findFeed(ObjC.Object(window), 0) : null;
    if (!coll) return;
    offsetY = Number(coll.contentOffset().y.toString());
    send({ source: 'scroll', json: coll.$className });
  }
  offsetY += 900;
  coll.setContentOffset_animated_({ x: 0, y: offsetY }, false);
}, 900);
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default=None)
    parser.add_argument("--seconds", type=float, default=40.0)
    parser.add_argument("--scroll", action="store_true")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    bridge = (Path(frida_tools.__file__).parent / "bridges" / "objc.js").read_text(encoding="utf-8")
    device = frida.get_device(args.device, timeout=30) if args.device else frida.get_usb_device(30)
    pid = device.spawn([BUNDLE_ID])
    session = device.attach(pid)

    source = bridge + "\n;globalThis.ObjC = bridge;\n" + PRELUDE + HOOKS + (SCROLL if args.scroll else "")
    script = session.create_script(source)

    out = open(args.out, "w", encoding="utf-8") if args.out else None
    summary = {}

    def on_message(message, data):
        if message["type"] == "error":
            print("error:", message.get("description"))
            return
        payload = message["payload"]
        if payload.get("source") == "scroll":
            print("scrolling", payload["json"])
            return
        try:
            info = json.loads(payload["json"]).get("text_app_music_info", {})
        except Exception:
            info = {}
        video = info.get("music_consumable_video") or {}
        shape = (
            tuple(sorted(video)),
            info.get("is_available_for_consumption"),
            info.get("error_code"),
        )
        summary[shape] = summary.get(shape, 0) + 1
        print("payload:", shape, "diagnostics:", payload.get("diagnostics"))
        if out:
            out.write(payload["json"] + "\n")
            out.flush()

    script.on("message", on_message)
    script.load()
    device.resume(pid)
    time.sleep(args.seconds)
    if out:
        out.close()
    print("\nsummary (video keys, available, error) -> count")
    for shape, count in summary.items():
        print(" ", shape, "->", count)


if __name__ == "__main__":
    main()
