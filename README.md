# ThreadsPulse

**English** | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md)

An iOS tweak for Threads (`com.burbn.barcelona`). Compatibility build: **1.31.0+16**, based on [ThreadsPulse 1.31.0 by h4x_0x30vm](https://github.com/mumuisdog/ThreadsPulse).

This fork retains the upstream features and adds compatibility fixes for Threads 410 and 456. Requires **iOS 15 or later**.

[Download 1.31.0+16](https://github.com/5hux1n/ThreadsPulse/releases/tag/1.31.0%2B16) · [All releases](https://github.com/5hux1n/ThreadsPulse/releases)

| Package | Environment |
|---|---|
| `ThreadsPulse_1.31.0+16_arm64.deb` | Rootless |
| `ThreadsPulse_1.31.0+16_arm64e.deb` | RootHide |

Install the matching DEB with your jailbreak package manager. For TrollFools, import the Rootless (`arm64`) DEB. No separate language resource bundle is required.

The built-in update checker follows the upstream project. Use this fork's Releases page for compatibility builds.

For IPA sideloading, see the local injection commands below. The Actions instructions describe the upstream workflow.

## Features

| Section | Feature | Description |
|---|---|---|
| Ads & Privacy | Block Ads | Hide sponsored posts in the feed |
| | Block Screenshot Detection | Threads won't know when you take a screenshot or record the screen |
| | Block Analytics | Stop Threads from sending usage data such as what you view, how long you stay and what you tap. Recommendations may become less accurate (off by default) |
| | Remove URL Tracking | Strip `xmt`, `igshid`, `utm_*` and more when copying, sharing or opening links, and unwrap `l.threads.com` redirects |
| | Hide Buttons in Screenshots | ThreadsPulse buttons don't appear in screenshots or screen recordings |
| Media Download | Download Button | ↓ at the top-right of a post: tap to download all photos and videos; long-press to choose photos or videos only |
| | Full-Screen Download | In full-screen view, ↓ sits next to "⋯": tap to save the image or video on screen; long-press to save all images or all videos in the post |
| | Download Original Size | Fetches the highest resolution from the web version; WebP is converted to JPEG for Photos |
| | Download Original Profile Pictures | Long-press the profile picture on a profile, or view it full screen and tap ↓ at the bottom right |
| | Parallel Downloads | Downloads up to 4 files at a time when saving an entire post; the progress window shows the speed |
| | Save to "Threads" Album | Downloaded items are also added to a "Threads" album in Photos (needs Full Access to Photos; off by default) |
| | Video Quality | Highest / 720p / Ask. Highest gets up to 1080p from Threads' DASH streams; VP9 and AV1 videos are converted on the device. Falls back to 720p if anything fails |
| | Video Format | Keep HDR (HEVC 10-bit, HLG/PQ kept) or Compatible (H.264 SDR) |
| Player | Disable Autoplay | Videos in the feed won't play until you tap them |
| | Default Playback Speed | 1x / 1.25x / 1.5x / 2x; videos return to it after you release a long-press 2x |
| Home Feed | Keep Feed Position | Coming back from the background won't refresh the home feed, jump to the top or switch tabs. Keep for 10 min / 30 min / No Limit |
| | Disable Pull to Refresh | Pulling down at the top of the home feed won't refresh it, and the feed stops at the top without bouncing |
| | When Tapping the Home Tab: Don't Scroll to Top | When you're scrolled down, tapping the Home tab keeps you where you were |
| | When Tapping the Home Tab: Don't Refresh | When you're at the top, tapping the Home tab won't refresh or load new posts |
| Author Info | Show Author Info | Shows details from the author's "About this profile" with their name in the feed (off by default) |
| | Location Stats | Counts the authors you've read by country, most common first; tap a country to list its authors and an author to open their profile |
| | Read Status & Cache | Shows how many authors are cached and whether reading is paused, or clears the cache |
| | Location | The country or region the account is based in, with its flag; shows "Not shared" when the author keeps it private |
| | Join Date | The month the account joined Threads |
| | Join Number | Which user number the account was when it joined, such as #7,551,963 or 100M+ |
| | New Account Badge | A green "NEW" tag on accounts that joined within the last 2 months |
| | Default Name Badge | A gray "Default Name" tag on accounts that never changed the username Threads assigned at sign-up (such as camel.253044); it doesn't mean the account is fake |
| | Show on Its Own Line | Adds a line under the name so the info always shows in full; when off, it sits next to the name and is shortened or hidden if there isn't enough room (on by default) |
| Hidden Items: Suggested Content | Suggested Accounts | Hide "Suggested for you" in the feed and on profiles |
| | Search Suggestions | Hide "Suggested to follow" on the search page |
| | Follow Suggestion Pop-ups | Stop "Follow suggestions" from popping up automatically |
| | Post Interest Prompts | Stop asking if you're interested in posts |
| Hidden Items: Interface Buttons | Search Button | Hide the search button on profiles (off by default) |
| | Instagram Button | Hide the Instagram button on profiles (off by default) |
| Links | Detect Copied Links | When you come back or switch accounts, detect a copied Threads link and open it |
| | When a Link Is Found | **Ask** shows a prompt (Top / Middle / Bottom); **Auto-open** opens it right away |
| | Open Links in External Browser | Links in posts and bios open in Safari (or your default browser) instead of the in-app browser. Threads links still open in the app |
| Messages | Hide Seen Status | Viewing messages won't notify the other person. To show "Seen" normally in a specific chat, tap the eye icon at the top right of that chat (off by default) |
| | Show Seen When You Reply | On: "Seen" shows to the other person only after you reply. Off: "Seen" won't show to the other person, even after you reply |
| | Reset Chats | Chats where you tapped the eye to show "Seen" go back to hiding it |
| | Hide Typing Status | The other person won't see "…" while you write a message (off by default) |
| | Keep Unsent Messages | When someone unsends a message, it stays in your chat marked "Unsent" (off by default) |
| Interface & Interactions | Like Confirmation | Ask before a like is sent, to prevent accidental taps. Removing a like won't ask |
| | Post Time Format | Relative / Date / + Year / + Seconds (the example under the options shows each format) |
| | Keep Tab Bar Visible | Scrolling won't hide the tab bar at the bottom |
| | Copy Profile Info | On a profile, long-press the name, username, bio or profile picture to copy the name, username or bio |
| | Long-Press Home Tab for Settings | Long-pressing the Home tab at the bottom opens ThreadsPulse settings instead (on by default) |
| Backup | Export / Import Settings | Export your settings to a JSON file, and import it after reinstalling or on another device |
| Advanced | Debug Hints | Turn on when a feature stops working. Hints show which features are active, to help report problems |
| | Analytics Log | Shows the usage data Threads collects and what it contains: a ranking of events with plain-language descriptions and the latest payload of each, ready to copy. The log never leaves your device |
| | Welcome Screen | See how to open ThreadsPulse settings again |
| | What's New | See this version's new features again (shown once automatically after an update; it can turn on Author Info) |
| | Check for Updates Automatically | Checks GitHub once a day and shows an alert when a new version is out, with Download, Later and Skip This Version |
| | Sideload Compatibility Fix | Keeps you signed in and app group data working after re-signing. Only active on re-signed apps |

**Theme**: in the info card at the top of the settings page, tap a color dot to switch (Coral / Ocean / Mint / Lavender / Sakura / Amber). It only changes the color of ThreadsPulse buttons and settings.

**Language**: in the same card, choose Follow System, English, 繁體中文, 简体中文, 日本語 or 한국어. ThreadsPulse's own text switches right away; Threads itself is unaffected.

**About** (last row of the Backup / Advanced card on the main page, with the version beside it): shows the ThreadsPulse version, Threads version, bundle ID, device model and iOS version with its build number, with Copy All Info, Check for Updates, a link to the source on GitHub, and Report a Problem, which opens a new GitHub issue with this information filled in. Reset All Settings is at the bottom of this page.

**Settings**: tap **〰 Pulse** at the top-right of Threads' Settings page, long-press the Home tab at the bottom, or long-press anywhere with three fingers for 1 second. A welcome screen explains these the first time you open Threads.

---

## Upstream IPA build workflow (reference)

### What you need

1. **A decrypted Threads IPA.** This project does **not** provide Threads itself. The App Store version is encrypted and won't work; you need a decrypted IPA.
2. **A direct download link to the IPA.** Put the IPA somewhere it can be downloaded directly (for example, a Dropbox link ending in `?dl=1`). Opening the link in a browser should start the download, not show a web page.
3. **A signing tool** to install the IPA on your phone. Your tool decides which variant to pick (see below).

### Two variants

| Variant | For | Contents |
|---|---|---|
| **sideload** | Certificate signing: ESign, Feather, Sideloadly with a paid developer account, etc. | Keeps Threads' own extensions (widgets, share, etc.) and adds the "Open in Threads" Safari extension |
| **noplugins** | **Free Apple IDs** with SideStore, AltStore, etc. | Removes all extensions. Free accounts can't sign extensions and have a limited number of App IDs |

**"Open in Threads" Safari extension**: a sideloaded Threads can't receive universal links, so tapping a threads.com link in Safari just stays on the web page. This extension turns threads.com / threads.net links into Threads app links and opens them: posts open the post, profiles open the profile.
After installing, go to **Settings › Apps › Safari › Extensions** (on iOS 17 and earlier: **Settings › Safari › Extensions**), turn on "Open in Threads", and allow it on threads.com.

### Set up your own repo (pick one)

| Method | Pros | Cons |
|---|---|---|
| **Fork** (easiest) | One click; tap **Sync fork** to get new versions | A fork is always **public** |
| **Import repository** (private) | Can be **private**, so only you can get the IPA | Re-import to get new versions |

- **Fork**: click **Fork** at the top-right of this project's page → **Create fork**.
  > **Anyone signed in to GitHub can download the Artifacts of a public repo**, and the IPA you build contains Threads itself. If you fork, save the IPA link as a Secret (see below) and delete the Artifact from the run page after downloading the IPA.
- **Import repository**: click **＋** at the top-right of GitHub → **Import repository**, paste this project's URL into **Your old repository's clone URL**, set **Privacy** to **Private** → **Begin import**.
  > Actions in private repos have a monthly free-minutes limit (macOS minutes count 10×). One build takes about 5–10 minutes.

### Steps

1. Open your repo → **Actions** tab. On a fork, first click "I understand my workflows, go ahead and enable them".
2. (Recommended) Save the IPA link as a Secret: **Settings → Secrets and variables → Actions → New repository secret**, name it `DECRYPTED_IPA_URL`, and paste the IPA link as the value.
3. Select **Build IPA** on the left → **Run workflow** on the right:
   - **ipa_url**: the IPA link. Leave it empty if you set the Secret.
   - **variant**: `both` (default, builds both), `sideload` or `noplugins`.
4. Click **Run workflow**. It takes about 5–10 minutes.
5. Open the run, and at the bottom under **Artifacts**, download `Threads_<version>_Pulse_<version>_sideload` or `…_noplugins`. Unzip it to get the IPA.
6. Install it with your signing tool. Artifacts are deleted automatically after 3 days.

**Common errors**

| Error | Cause |
|---|---|
| The downloaded file is not an IPA | The link opens a web page instead of downloading directly |
| This IPA is not decrypted | It's the encrypted App Store version; use a decrypted IPA |
| Not enough header space in the executable | Very rare; please report your Threads version |

> Please don't upload the IPA to a public Release or anywhere public.

---

## Other ways to build

### Prebuilt packages

Download the Rootless and RootHide DEBs from [Releases](https://github.com/5hux1n/ThreadsPulse/releases). These packages are built locally with Xcode 16. The upstream Actions packaging matrix is not used for this compatibility fork's releases.

### Build locally

Requires macOS, Xcode 16, Python 3 and [Theos](https://theos.dev). Use the [RootHide Theos fork](https://github.com/roothide/theos) for RootHide packages.

```bash
export THEOS=~/theos
make FINALPACKAGE=1            # dylib only: .theos/obj/ThreadsPulse.dylib
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless    # Rootless .deb
make -C OpenThreadsSafariExtension FINALPACKAGE=1   # Safari extension → OpenThreadsSafariExtension/.theos/obj/

# Inject into a decrypted IPA (only needs Python 3 and zip / unzip)
# sideload variant
python3 scripts/inject_ipa.py -i Threads.ipa -d .theos/obj/ThreadsPulse.dylib \
  --appex OpenThreadsSafariExtension/.theos/obj/OpenThreadsSafariExtension.appex -o sideload.ipa
# noplugins variant
python3 scripts/inject_ipa.py -i Threads.ipa -d .theos/obj/ThreadsPulse.dylib \
  --no-plugins -o noplugins.ipa
```

For RootHide, build with its own Theos installation:

```bash
THEOS=~/theos-roothide make clean THEOS_PACKAGE_SCHEME=roothide
THEOS=~/theos-roothide make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

Both packages are written to `dist/` as `ThreadsPulse_<version>_arm64.deb` and `ThreadsPulse_<version>_arm64e.deb`.

- Uses the Logos `internal` generator to hook through the ObjC runtime directly, so it **doesn't depend on CydiaSubstrate / ElleKit** and nothing extra needs to be injected.
- The displayed version number is defined in `TPVersion.h`; language metadata is in `resources/localization/Info.plist`. The iOS SDK and minimum iOS version are set by `SDK_VERSION` and `MIN_IOS` in the workflows.

### What `inject_ipa.py` does

1. Unpacks the IPA and copies `ThreadsPulse.dylib` into `Threads.app/Frameworks/`. Current builds embed their translations; the optional `--bundle` argument retains support for older builds that need a separate `ThreadsPulse.bundle`.
2. Adds an `LC_LOAD_DYLIB` load command (`@executable_path/Frameworks/ThreadsPulse.dylib`) to the Threads executable, skipping it if already there.
3. Checks that the app is decrypted (`cryptid` in `LC_ENCRYPTION_INFO_64`) and stops if it isn't.
4. `--appex` copies an extension into `PlugIns/` (removing any signing data inside it); `--no-plugins` removes `PlugIns/`, `Extensions/` and `Watch/`.
5. Repacks an **unsigned** IPA for your signing tool to sign.

It only uses the Python standard library; nothing else to install.

---

## Project structure

```
ThreadsPulse/
├── Makefile
├── control                         Package info
├── ThreadsPulse.plist              Injection target (com.burbn.barcelona)
├── Tweak.x                         All hooks (Logos)
├── TPPrefs.h/.m                    Settings storage, defaults, export / import
├── TPURLCleaner.h/.m               URL tracking removal
├── TPDownloader.h/.m               URL selection, downloads, WebP → JPEG, DASH 1080p (merge / VP9 & AV1 conversion), diagnostics
├── TPHUD.h/.m                      Progress view, toasts, prompt banner
├── TPUI.h/.m                       Round frosted buttons, long-press menus, haptics, theme colors
├── TPSettingsViewController.h/.m   Settings page
├── TPWelcomeViewController.h/.m    Full-screen welcome screen shown on first launch
├── TPLocalization.h/.m             TPL() localization
├── TPSideloadFix.h/.m              Sideload compatibility fix (keychain, app groups)
├── TPUpdateChecker.h/.m            Checks GitHub Releases for a new version
├── vendor/libvpx/                  Prebuilt VP9 decoder (arm64 iOS, static) + headers, LICENSE
├── vendor/dav1d/                   Prebuilt AV1 decoder (arm64 iOS, static) + headers, COPYING
├── TPVersion.h                     Version number (change it only here)
├── ThirdPartyLicenses/             Licenses of borrowed material (lee-su-threads)
├── scripts/inject_ipa.py           Injects the tweak into an IPA
├── OpenThreadsSafariExtension/     "Open in Threads" Safari extension (sideload variant only)
│   ├── OpenInThreadsHandler.m      Native side (only lets the extension load)
│   └── Resources/                  content.js (link conversion and redirect), manifest.json, icons
├── .github/
│   ├── actions/setup-theos/        Shared: installs Theos and the iOS SDK
│   └── workflows/
│       ├── build.yml               Builds the tweak (zip / deb)
│       └── build-ipa.yml           Builds and injects the IPA
└── resources/localization/         Embedded into ThreadsPulse.dylib at build time
    ├── Info.plist
    ├── en.lproj/Localizable.strings
    ├── zh-Hant.lproj/Localizable.strings
    ├── zh-Hans.lproj/Localizable.strings
    ├── ja.lproj/Localizable.strings
    └── ko.lproj/Localizable.strings
```

## Localization

- The code always uses `TPL(@"English text")`; **the English text is the key**, and it's shown as-is when no translation exists.
- Included languages: English (`en`), Traditional Chinese (`zh-Hant`), Simplified Chinese (`zh-Hans`), Japanese (`ja`) and Korean (`ko`). By default the system language is used (anything else falls back to English); the Language row at the top of the settings can force one.
- Translation sources live in `resources/localization/`; `scripts/generate-localization.py` embeds them into the dylib during the build, so no separate `.bundle` is needed. To add a language, copy `en.lproj` (for example to `fr.lproj`), translate it, add the language code to `CFBundleLocalizations` in `Info.plist`, and update the Language menu (`TPSettingsViewController.m`), `TPLocalization.m` and the generator's supported-language mapping.
- Corrections to the Simplified Chinese, Japanese and Korean translations from native speakers are welcome.

## Implementation notes

- **Swift classes**: hooked by mangled name (for example `_TtC6BCNUFI12BCNUFIButton`), with ivars read through the runtime. Pointers and classes are validated before reading Swift enum memory, to avoid crashes.
- **Batch download**: reads every item from the carousel cell's data model (`BCNFeedMediaViewModel` → `IGPhoto` / `IGVideo`), unaffected by cell reuse.
- **1080p videos**: the progressive MP4 Threads exposes tops out at 720p. The higher qualities only exist in the DASH manifest (`IGVideo.dashManifestData`), as separate video and audio streams. The best video (by resolution) and audio (AAC preferred over Opus) are downloaded and combined on the device: H.264 / HEVC are copied as-is (`AVAssetExportSession` passthrough, or `AVAssetWriter` when the audio has to be re-encoded); VP9 is decoded with libvpx, and AV1 by the system (VideoToolbox) on devices with hardware AV1 decoding (iPhone 15 Pro and later, iOS 17+) or with dav1d elsewhere, then re-encoded with VideoToolbox — HEVC Main10 when the codec string says HLG/PQ (Keep HDR), otherwise H.264; with Compatible, HDR frames are converted to BT.709 by `VTPixelTransferSession` first. Any failure falls back to the 720p MP4, never to a silent video. A progressive MP4 that turns out to be AV1 or VP9 (which Photos rejects) goes through the same conversion. Downloads ask iOS for background time, and a conversion cut off because Threads went to the background resumes when you return. "Ask" shows the choice as a menu next to the button that was tapped.
- **Parallel downloads**: items after the current one are fetched ahead on a second `NSURLSession` (3 connections + the main one); saving to Photos stays in order.
- **Original-size photos / profile pictures**: fetches `https://www.threads.com/t/<code>` or `/@<username>` and picks the largest candidate from the page JSON by matching file names.
- **Clipboard**: first checks for a URL with `detectPatternsForPatterns:` (no paste prompt); the content is only read when you tap Open or use Auto-open. The link is handed to Threads through `NSUserActivity` (BrowsingWeb).
- **Account switching**: hooks `IGAccountSwitcher` and checks the clipboard 1.5 s after the last switch event; 0.8 s after returning from another app.
- **Keep Feed Position**: passes 0 seconds to `applicationWillWarmStartWithTimeIntervalSinceBackgrounded:` (home feed and `BCNAppViewController`), sets the feed's `lastBgTime` to now before it comes to the foreground, and raises the server thresholds in `IGFeedRefreshInstructionsStore` to the keep time.
- **Pull to refresh**: in the home feed's `scrollViewDidScroll:`, the offset is kept from going past the top while dragging, so the refresh control never triggers.
- **Home tab**: with the new tab bar (`BCNLucentTabBarCoordinator`), re-selecting the same tab first checks whether the feed is at the top, then decides whether Threads gets to handle the tap (`tabBarController:shouldSelectTab:`, `didSelectTab:previousTab:`, `handleTabBarDoubleTap:`). The legacy tab bar (`BCNLegacyTabBarController`) decides in Swift where it can't be intercepted, so the tap time is recorded and upward scrolls / refreshes of the feed are blocked for 1 s. These fallback hooks are only installed the first time the legacy tab bar is tapped.
- **Keep Tab Bar Visible**: keeps `scrollViewDidScroll:` / `scrollViewDidEndScrolling:` from reaching `BCNLucentTabBarCoordinator`, and sets iOS 26's `tabBarMinimizeBehavior` to never.
- **Sideload Compatibility Fix**: on load, stores a probe item in the keychain and reads back the access group the system actually assigned. It only activates when the Team ID isn't Meta's (`MH9GU9K5PX`). It rewrites `SecItemAdd` / `CopyMatching` / `Update` / `Delete` in the symbol pointer tables of the app's own images (main executable and `Frameworks/`) to swap Threads' access groups for the usable one, and falls back to `Library/ThreadsPulseAppGroups/<group>` when `containerURLForSecurityApplicationGroupIdentifier:` returns nil. Threads doesn't use iCloud, so CloudKit isn't touched.
- **Copy Profile Info**: copies the name (`fullNameLabel`), username (`usernameLabel`, without `@`) or bio. Adds long-press gestures to the profile picture, `fullNameLabel`, `usernameLabel` and `IGProfileBioView` in `BCNProfileHeaderView`. The full bio comes from `_fullCollapsibleBioString` (when collapsed) or `_stringForView`. When the feature is off the gestures don't begin, so Threads' own long-press works as usual.
- **Hide Search / Instagram Button**: hides `$__lazy_storage_$_searchButton` and `$__lazy_storage_$_appSwitcherButton` of `BCNProfileViewController` in `viewDidLayoutSubviews`, together with any wrapper view that holds only them. Inside a stack view the gap closes by itself; otherwise the buttons in the same row are shifted with a transform to fill it (when both are hidden, the larger shift is used rather than the sum).
- **Suggested Accounts / Search Suggestions**: `BCNAYMFSectionController` (the "Suggested for you" unit) is checked by its `placement`: 0 (home feed) and 3 (profiles) follow Suggested Accounts, 2 (search page) follows Search Suggestions.
- **Post Interest Prompts**: `BCNFeedItemSeeMoreSeeLessCell` returns a height of 0 and is hidden, and the batched prompt's section controller returns 0 items.
- **Open Links in External Browser**: hooks both `handleLinkWithURL:` methods of `BCNLinkHandlerImpl` (an ObjC protocol, so calls go through ObjC dispatch). `l.threads.com` redirect wrappers are unwrapped first; `threads.net` / `threads.com` and non-web links keep the original behaviour, everything else is opened with `-[UIApplication openURL:]` (tracking parameters are removed when Remove URL Tracking is on).
- **Three-finger long-press**: the recognizer runs simultaneously with others and, once it begins, briefly disables the other recognizers on the same touches, so lifting your fingers doesn't also trigger the button you first touched.
- **Long-Press Home Tab for Settings**: hooks `-[BCNLucentTabBarCoordinator handleTabBarLongPress:]`. When the press begins on the first (Home) tab button, ThreadsPulse settings open and the rest of that gesture is swallowed; long-presses on other tabs (e.g. switching accounts on the profile tab) work as usual.
- **Hide Seen Status**: `+[BCNSlideMDCoreMarkThreadReadMutationBuilder builderWithOfflineThreadingId:threadFbid:timestampMs:]` is called with the position this chat has already shown to the other person (0 if none), so the read position on the server neither moves forward nor goes back; the thread still shows as read on your side. The eye icon at the top right of a chat lets that chat send reads as usual.
- **Show Seen When You Reply**: when Threads builds an outgoing message (`BCNSlideOutgoingMessagePayload`) or a message action (`BCNSlideOutgoingMessageUpdatePayload`), the read request is rebuilt from the stored arguments and sent through the same GraphQL service Threads uses for reads. The message is held in `-[MDCoreSendService sendMutationWithAppDataModel:…]` until the server accepts the read (0.8 s at most), so the other person sees "Seen" before your reply arrives.
- **Hide Typing Status**: the status passed to `+[BCNTypingIndicatorPublishEventMutationBuilder builderWithActivityStatus:threadId:]` is always set to 0 (stopped typing). The thread ID is left alone, so live message delivery isn't affected.
- **Keep Unsent Messages**: an incoming unsend is handled by Swift's `BCNSlideDeleteMessageHandler`, which reaches the local store through `MDCoreDeltaApplyingBridge` (created with the handler's type name). When the setting is on, the delete commands returned by `mutationCommandsForDeltaWithRequestedState:…` for that handler are removed, so the message stays on your device and is marked "Unsent" right away (the label stays even if you turn the setting off later). Messages that were already removed, or that disappear when the chat is fully reloaded from the server, can't be brought back.
- **Block Analytics**: usage events are dropped where they are collected (`-[FBAnalyticsCoreLogger _captureAnalyticsEvent:]`, `_captureAnalyticsEventForBatchUpload:`, and `_shouldStreamEvent:` returns NO), and uploads of anything already stored go through Meta's own `FBAnalyticsNoOpNetworkConfigurator` instead of `IGAnalyticsNetworkConfigurator`, so no request is sent. Normal API calls (login, posting, loading the feed) don't go through this path.
- **Analytics Log**: `_captureAnalyticsEvent:` counts each `FBAnalyticsEvent` by `eventName` and keeps the latest event object of each kind; `eventPayload` is only read when you open the log. Everything stays in memory and is cleared when the app closes.
- **Disable Autoplay**: when a feed video scrolls into view (`-[IGFNFVideoPlayer playWithReason:callsiteContext:]`, reason 1), Threads is allowed to start playback as usual so its UI (including the sound icon) appears, but the underlying `FNFPlayer` is held: its first `play` runs with volume 0 so Threads reaches "initial play" and shows the sound icon, then it is paused on the first frame (`videoPlayerDidInitialPlay:`); later `play` / `playWithContext:` calls are ignored. Tapping the video (a touch that barely moved, so scrolling doesn't count) releases the hold and starts `FNFPlayer`. Other play reasons (full screen, etc.) and videos outside the feed play as usual. Once started, the same player isn't held again until it's stopped. The single-video download button now reads the URL from nearby data objects first, so videos that never played can still be downloaded.
- **Author Info**: calls Threads' own `BKSharedAsyncActionDataFetcher` with `com.bloks.www.text_post_app.about_this_profile_async_action` to get "About this profile", then reads the country (the `about_this_profile_country` state) and the "Joined" row from the returned Bloks layout. The request needs a `BKObjectSet` that carries the signed-in session: the `IGUserSession` and `PNPandoGraphQLService` are noted at launch and assembled into one (with an `IGSessionContext`); if the first try crashes this is disabled for good and the set Threads creates when it opens a Bloks screen is borrowed instead. The author ID is the Swift `userPk` of `BCNFeedItemHeaderProfilePicture`. Rate-limit protection: one author at a time, 1.5 s apart, at most 10 queued and 400 per launch; a 429, `feedback_required` or spam response pauses reading for 1 hour; results with a location are cached for 21 days, without one for 1 day. Own line: when `BCNFeedSectionController` builds the name row's cell its row is remembered, and `sizeForItemAtIndex:` adds one line of height before the section is re-laid out.
- **Hide Follow Suggestions**: intercepts `presentViewController:` when `BCNUserRecommendationsViewController` is presented as a sheet; pushed pages aren't affected.

## Notes

When Threads updates, some features may stop working for a while (no crash). Turn on Debug Hints to see which one, and feel free to report it.

## Third-party libraries

| Library | Use | License |
|---|---|---|
| [libvpx](https://chromium.googlesource.com/webm/libvpx) | VP9 decoding | BSD 3-Clause (`vendor/libvpx/LICENSE`, `PATENTS`) |
| [dav1d](https://code.videolan.org/videolan/dav1d) | AV1 decoding | BSD 2-Clause (`vendor/dav1d/COPYING`) |

Both are bundled as prebuilt static libraries; the exact commit and build options are in each folder's `VERSION.txt`.

### Acknowledgements

Author Info (location, join date and new-account badge in the feed) draws on [lee-su-threads](https://github.com/meettomorrow/lee-su-threads) by meettomorrow (MIT License). ThreadsPulse's code is its own, but it follows that project's approach (label parsing, cache durations, the 1-hour rate-limit pause) and uses its default-username rule and animal word list. Its license is included in `ThirdPartyLicenses/lee-su-threads.txt`.

## Disclaimer

1. This project is independently developed, unofficial software. It is not affiliated with, sponsored, authorized or endorsed by Meta Platforms, Inc. ("Meta") or Apple Inc. "Threads" and related marks are trademarks of Meta and are used here only to identify compatibility.
2. This project does not include or distribute the Threads application or any part of it. Users must obtain any required files lawfully and must not publicly distribute modified applications.
3. Modifying third-party applications may violate the applicable terms of service and may result in account restrictions, suspension or other consequences. Users assess and bear these risks on their own.
4. All content downloaded through this project remains the property of its respective rights holders. Users may only use it for personal purposes to the extent permitted by law and must not infringe the rights of others.
5. This project is provided "as is", without warranty of any kind, express or implied. In no event shall the author be liable for any direct, indirect, incidental or consequential damages arising from the use of, or inability to use, this project.
6. By downloading, building or using this project, you acknowledge that you have read, understood and agreed to this disclaimer in full.

## Author

h4x_0x30vm · [Ko-fi](https://ko-fi.com/mumuisdog)

Compatibility modifications: [Junhong](https://mjh.im/)

© 2026 h4x_0x30vm. All rights reserved.
