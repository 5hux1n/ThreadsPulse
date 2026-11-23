# Unsent push notification investigation

## Confirmed scope

The current `KeepUnsent` group filters local message deletion commands from
`MDCoreDeltaApplyingBridge` and `MDCoreDeleteMessageDeltaApplicator`, then labels retained
message cells. Notification handling runs separately in the notification extension;
the combined dylib filter targets Threads and BarcelonaNotificationExtension.

Both local IPA versions contain this separate notification service extension:

| Property | Threads 410 | Threads 456 |
| --- | --- | --- |
| Executable | BarcelonaNotificationExtension | BarcelonaNotificationExtension |
| Bundle identifier | com.burbn.barcelona.NotificationServiceExtension | com.burbn.barcelona.NotificationServiceExtension |
| Extension point | com.apple.usernotifications.service | com.apple.usernotifications.service |
| Principal class | FBNotificationService | FBNotificationService |

`FBNotificationService` inherits from `UNNotificationServiceExtension` and exposes
`didReceiveNotificationRequest:withContentHandler:`. Both extension binaries contain
`BCNSlideNotificationRevoker`, `revoke_notification`, and `unsend` identifiers.

Neither extension contains `.strings` or `.stringsdict` files. The exact English notification
body `A message was unsent`, with or without a final period, was not found in either
extension executable. Its absence does not establish whether the text comes from the
server or a shared framework.

## Binary analysis boundary

Although the IPA main executables are available for analysis, both extracted notification
extensions retain `LC_ENCRYPTION_INFO_64` with `cryptid = 1`:

| Version | Encrypted file offset | Encrypted size |
| --- | ---: | ---: |
| 410 | 2,539,520 | 4,096 |
| 456 | 4,075,520 | 4,096 |

The first attempt to open the 410 extension in IDA was rejected by its encrypted-file
check. No repeated IDA import or environment repair was attempted. This was an import
boundary, not an explanation for abandoning the binary: Ghidra subsequently analyzed
the 410 extension. The marked 410 range is VA `0x10026c000..0x10026d000`; its `__text`
ends at `0x10026c2dc`. The marked 456 range is VA `0x1003e3000..0x1003e4000`; its
`__text` ends at `0x1003e3990`. Thus only the last part of `__text` and first part of
`__stubs` overlap the marked page. The native revoke predicates below lie outside it.

The existing 410 main-app IDA database was reused for bounded inspection, then this
task's lease was released. In both main-app metadata dumps,
`BCNSlideNotificationRevoker` exposes only Objective-C `init`. The only class method on
`IGNotificationRevokingHelper` is the logging method
`_logEventWithName:extras:analyticsLogger:`, not an unsend interception method.
`IGPushNotificationInfo` exposes `notificationType`, `userInfo`, recipient identifiers,
and generic notification state. Those main-app declarations alone did not establish
the event value; the separate extension predicates did.

## Exact native revoke marker

Both versions' revoker predicates return true for the same string comparison:

```objc
[content.userInfo[@"c"] isEqualToString:@"text_post_app_recall_notif"]
```

This is a typed native event marker. A normal message merely containing the English
sentence does not meet this condition. The check was established from the following
bounded static paths, rather than inferred from nearby analytics strings.

| Evidence | Threads 410 | Threads 456 |
| --- | --- | --- |
| Revoke predicate | `0x100108b74` | `0x1003b0758` |
| Key CFString | `0x1003fc880` = `c` | `0x1005f8810` = `c` |
| Event CFString | `0x1004036e0` = `text_post_app_recall_notif` | `0x1005f8b50` = `text_post_app_recall_notif` |
| Comparison | Swift string equality, returned bool | Swift string equality, returned bool |

For 410, helper `0x10022bf48` loads the key through global `0x1003d5ce8`; helper
`0x10022bf54` loads the event string through global `0x1003d3238`. The generated
`barcelona_nse_revoker_plugin` configuration at `0x1003cac38` contains callback
indices `[12, 14, 15, 16]`. Function table lookup `0x1001122b4` reads from
`0x1003caca0`; index 14 resolves to wrapper `0x100258928`, which passes the
predicate address `0x100108b74`. Index 16 resolves to wrapper `0x100258274`, which
passes the actual deletion mutator address `0x100108a6c`. These outlined wrappers
explain why a direct function-xref lookup did not reveal the call chain.

`BCNSlideNotificationRevoker.init` at `0x10011ce1c` is only base construction:
the imported stubs are `swift_getObjectType` and `objc_msgSendSuper2`. It does not
register a handler or identify a revoke event.

## Removal and notification identifiers

The 410 mutator `0x100108a6c` reads `pluginContent.content.userInfo[@"gid"]`,
converts a string value to a one-element identifier array, and invokes
`removeDeliveredNotificationsWithIdentifiers:` before completing the plugin step.
The corresponding 456 route is `0x1003b08ec` through helper `0x100399494`.

The extension's `UNNotificationContent.messageId` derives from `userInfo[@"n"]`.
Its `isSlideNotification` only checks whether the `ig` URL's last path component starts
with `slide`; this is not an unsend marker. Neither `n` nor a shared thread identifier
should be substituted for `gid` without following the actual request-identifier mapping.

Static evidence now supports a precisely scoped language fallback for native recall
events. Preserving original notification text additionally requires the original
request identifier, the delivered-content lookup, and removal/replacement timing.
Do not claim original-content preservation solely because the deletion call is found.

## Current notification implementation (+16)

ThreadsPulseNotifications.x is compiled into the single ThreadsPulse.dylib.
Its constructor matches BarcelonaNotificationExtension; the main tweak constructor
returns immediately outside Threads. No extra load-time initializers were found in
the main sources or vendor archives. The constructor verifies both native service methods
before installing the hook, without requiring a fixed extension bundle identifier.

The language fallback requires an exact recall marker in the original or final content,
then an exact final body of “A message was unsent” or “A message was unsent.”. Only body
is changed. Ordinary messages containing the same English sentence remain untouched.
Five built-in strings follow NSLocale.preferredLanguages, with English fallback. The
notification path does not read external bundle resources or main-app defaults.

### Optional body recovery

Only the KeepUnsent boolean is mirrored to a dedicated atomic plist in the real common
AppGroup group.com.burbn.instagram. Missing, malformed, inaccessible, or non-boolean
state means recovery is off. Main-app launch, activation, setter, reset and import keep
this mirror current. The file uses protection allowing reads after first unlock. No
notification body is written to this file.

For an incoming exact recall marker with a nonempty string gid and recovery enabled:

1. Query still-delivered notifications before native processing deletes the old one.
2. Match only delivered.request.identifier == request.content.userInfo[@"gid"].
3. Read only that candidate body; reject whitespace-only bodies and recall notifications.
4. Resume native processing on the main queue, with a 350 ms lookup deadline.
5. At native completion, if KeepUnsent is still on, copy the final content and replace
   only body with the recovered original. This also works for already-localized recall text.
6. Without a match, retain the existing language fallback. Never invent a body.

The original request, identifier and trigger are never rebuilt. The final title, metadata,
actions, attachments and sound remain native. Plaintext is held only in the current
request's memory, without a persistent message cache.

On normal native completion with successful recovery, native code still deletes the old
gid notification. The new recall notification displays the old body with the new
notification's time and identifier. An expiry-first fallback instead completes from the
saved request content and any body recovered so far; native processing may not have run,
so this path does not establish native deletion or final native metadata. Notifications
already cleared, not delivered, or delivered without a plaintext preview cannot be
reconstructed.

Both 410 and 456 normally call _contentComplete:YES from serviceExtensionTimeWillExpire.
Ordinary requests keep that native path. Recovery requests retain a one-shot fallback
through lookup and native handoff: expiry on another thread completes immediately using
the original request content and any recovered body, without waiting for the main queue
or a native handler that may not yet have been saved. A completion latch rejects late
queries, deadlines and duplicate native callbacks. If iOS bypasses or kills the extension,
these hooks cannot control its payload fallback.

Logs prefixed [ThreadsPulseNotifications] contain version, hook readiness, recall match,
language and translated/restored flags only. They never contain bodies, sender data,
userInfo contents, message identifiers or conversation identifiers.

## Single-file resources

The five localization tables formerly in ThreadsPulse.bundle are embedded in the main
dylib. The source tables remain editable build inputs, with no runtime bundle extraction.
The setting still supports automatic system selection and all five manual languages.

## Injection and verification boundary

The user confirmed TrollFools DEB import on a jailbroken device. Upstream 4.4.2 source at
commit c5c87b859a9ee34d215548377273eddd34a7c7f6 was inspected locally. It extracts dylibs
and bundles, then injects the selected app's main executable or framework. It does not
use the tweak Filter plist or enumerate the notification .appex as another injection target.
One merged dylib does not change this limitation: the dylib must load into
PlugIns/BarcelonaNotificationExtension.appex/BarcelonaNotificationExtension for either
notification localization or body recovery to run.

Normal jailbreak DEB installation lets the loader honor the executable filter for both
processes. Do not also leave an injected duplicate in the app. This work does not modify
TrollFools, patch an installed app bundle or target any system process.

Local tests execute the actual production hook and constructor with UserNotifications
stubs, exercising exact matches, metadata, languages, enable/disable changes, lookup
deadlines, native handoff, expiry and duplicate callbacks. Preference tests use real
Foundation file IO and isolated source defaults. None of these tests establishes real
AppGroup access, locked-device access, extension injection or successful push retention.
Those still require the push-capable overseas device; mainland testing cannot replace it.
