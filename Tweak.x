// ThreadsPulse: hooks for Threads (com.burbn.barcelona).
//
// Class and selector names come from a class-dump of the Threads executable. Many of them
// are Swift classes, hooked by their mangled names. When Threads renames something the hook
// simply stops matching, so a broken feature fails quietly instead of crashing. Debug Hints
// in the settings shows which hooks are still firing.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import "TPPrefs.h"
#import "TPURLCleaner.h"
#import "TPDownloader.h"
#import "TPSettingsViewController.h"
#import "TPLocalization.h"
#import "TPUI.h"
#import "TPHUD.h"
#import "TPVersion.h"
#import "TPSideloadFix.h"
#import "TPWelcomeViewController.h"

// Swift classes have no usable headers, so methods called on them are declared here and
// `self` is cast to id or UIView * before use.
@interface NSObject (TPDecl)
- (void)tp_threeFingerLongPress:(id)gesture;
- (void)setPlaybackSpeed:(float)speed;
- (BOOL)isPlaying;
- (void)play;
- (void)pause;
- (void)setVolume:(float)volume rampTime:(float)time;
- (id)videoPlayer;
- (id)imageURLForWidth:(double)width;
@end

static NSURL *TPBestImageURLFromPhoto(id photo);
static NSMutableString *gTPSizeLog;
static NSInteger gTPSizeIndex;

static NSInteger gTPOwnPasteboardChange = -1;

static void TPDebugNow(NSString *msg) {
    if (![TPPrefs boolForKey:TPKeyDebugToast]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [TPHUD toast:[@"[TP] " stringByAppendingString:msg]]; });
}

static void TPDebug(NSString *msg) {
    if (![TPPrefs boolForKey:TPKeyDebugToast]) return;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last < 2.0) return;
    last = now;
    [TPHUD toast:[@"[TP] " stringByAppendingString:msg]];
}

static UIView *TPFindView(UIView *root, Class cls, int maxDepth) {
    if (!root || !cls || maxDepth < 0) return nil;
    if ([root isKindOfClass:cls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *f = TPFindView(sub, cls, maxDepth - 1);
        if (f) return f;
    }
    return nil;
}

static NSArray *TPCleanItems(NSArray *items) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
    for (id it in items) {
        if ([it isKindOfClass:[NSURL class]])         [out addObject:[TPURLCleaner cleanURL:it]];
        else if ([it isKindOfClass:[NSString class]]) [out addObject:[TPURLCleaner cleanString:it]];
        else                                          [out addObject:it];
    }
    return out;
}

// Ads are blocked at three stages: the ad request, the sponsored items that come back, and
// the insertion into the feed. Any one stage is enough; the others cover Threads changing
// which path it uses.
%group Ads

%hook _TtC15IGBCNAdsManager15IGBCNAdsManager
- (void)startNewAdDeliveryWithSurfaceDelegate:(id)delegate sessionId:(id)sid analyticsModule:(id)module {
    if ([TPPrefs boolForKey:TPKeyBlockAds]) { TPDebug(TPL(@"Blocked an ad request")); return; }
    %orig;
}
- (void)processSponsoredItems:(id)items projectedItems:(id)projected analyticsModule:(id)module {
    if ([TPPrefs boolForKey:TPKeyBlockAds]) { TPDebug(TPL(@"Dropped sponsored items")); return; }
    %orig;
}
%end

%hook _TtC15IGBCNAdsManager37BCNMainFeedAdsInsertionSurfaceHandler
- (void)adInsertionHandler:(id)handler shouldTryToInsertSponsoredItem:(id)item
          atInsertionIndex:(long long)index focusedIndex:(long long)focused insertionContext:(id)ctx {
    if ([TPPrefs boolForKey:TPKeyBlockAds]) { TPDebug(TPL(@"Blocked ad insertion")); return; }
    %orig;
}
- (void)receivedSponsoredItems:(id)items intentAwareData:(id)data {
    if ([TPPrefs boolForKey:TPKeyBlockAds]) return;
    %orig;
}
- (void)adPlatformDidDeliverSponsoredItem:(id)item atAdRequestIndex:(long long)index {
    if ([TPPrefs boolForKey:TPKeyBlockAds]) return;
    %orig;
}
%end

%hook IGAdFetcherManager
- (void)adFetcher:(id)fetcher didReturnAdsResponse:(id)response paginationInfo:(id)info
  requestMetadata:(id)meta isFromCache:(BOOL)cache adRequestExtraInfo:(id)extra {
    if ([TPPrefs boolForKey:TPKeyBlockAds]) return;
    %orig;
}
%end

%end

%group Tracking

%hook UIPasteboard
- (void)setURL:(NSURL *)url {
    NSURL *c = [TPURLCleaner cleanURL:url];
    if (![c isEqual:url]) TPDebug(TPL(@"Cleaned tracking from copied link"));
    %orig(c);
    gTPOwnPasteboardChange = [(UIPasteboard *)self changeCount];
}
- (void)setString:(NSString *)string {
    %orig([TPURLCleaner cleanString:string]);
    gTPOwnPasteboardChange = [(UIPasteboard *)self changeCount];
}
- (void)setItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in items) {
        NSMutableDictionary *nd = [NSMutableDictionary dictionary];
        [d enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
            if ([v isKindOfClass:[NSURL class]])         nd[k] = [TPURLCleaner cleanURL:v];
            else if ([v isKindOfClass:[NSString class]]) nd[k] = [TPURLCleaner cleanString:v];
            else                                         nd[k] = v;
        }];
        [out addObject:nd];
    }
    %orig(out);
    gTPOwnPasteboardChange = [(UIPasteboard *)self changeCount];
}
%end

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)acts {
    return %orig(TPCleanItems(items), acts);
}
%end

%hook IGExternalURLIntentTarget
- (id)initWithTargetURL:(NSURL *)url mediaPk:(id)mediaPk authorPk:(id)authorPk {
    return %orig([TPURLCleaner cleanURL:url], mediaPk, authorPk);
}
%end

%hook UIApplication
- (void)openURL:(NSURL *)url options:(NSDictionary *)opts completionHandler:(void (^)(BOOL))handler {
    %orig([TPURLCleaner cleanURL:url], opts, handler);
}
%end

%end

static Class TPFeedMediaCellClass(void) {
    static Class c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = NSClassFromString(@"_TtC16BCNFeedMediaCell16BCNFeedMediaCell"); });
    return c;
}

static Class TPVideoViewClass(void) {
    static Class c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = NSClassFromString(@"_TtC11IGVideoView11IGVideoView"); });
    return c;
}

static BOOL TPInsideFeedMediaCell(UIView *v) {
    Class c = TPFeedMediaCellClass();
    if (!c) return NO;
    for (UIView *s = v.superview; s; s = s.superview) if ([s isKindOfClass:c]) return YES;
    return NO;
}

// Single-video download button.
// IGVideoView is a Swift class whose methods Threads calls directly, bypassing ObjC dispatch.
// The button is attached from UIKit methods that always go through ObjC (didMoveToWindow,
// layoutSubviews), and the video URL is only resolved when the button is tapped.
static const void *kTPButtonKey = &kTPButtonKey;
static const void *kTPPlayerKey = &kTPPlayerKey;

static const void *kTPPlayerViewKey = &kTPPlayerViewKey;

@interface TPWeakBox : NSObject
@property (nonatomic, weak) id object;
@end
@implementation TPWeakBox
@end

static void TPPauseIfHeld(id player);

static id TPInnerPlayer(id player) {
    if (![player respondsToSelector:@selector(videoPlayer)]) return player;
    id inner = [player videoPlayer];
    return inner ?: player;
}

static inline void TPRememberPlayer(id view, id player) {
    if (!player || objc_getAssociatedObject(view, kTPPlayerKey) == player) return;
    objc_setAssociatedObject(view, kTPPlayerKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TPWeakBox *box = [TPWeakBox new];
    box.object = view;
    objc_setAssociatedObject(player, kTPPlayerViewKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id inner = TPInnerPlayer(player);
    if (inner != player) objc_setAssociatedObject(inner, kTPPlayerViewKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void TPEnsureVideoButton(UIView *host) {
    UIButton *b = objc_getAssociatedObject(host, kTPButtonKey);
    CGSize sz = host.bounds.size;
    BOOL want = host.window && [TPPrefs boolForKey:TPKeyShowDownloadBtn] && sz.width >= 120 && sz.height >= 120
                && !TPInsideFeedMediaCell(host);
    if (!want) { b.hidden = YES; return; }

    const CGFloat d = 38;
    if (!b) {
        __weak UIView *weakHost = host;
        b = [TPUI circleButtonWithSymbol:@"arrow.down.to.line" diameter:d onTap:^{
            UIView *v = weakHost;
            if (!v) return;
            id player = objc_getAssociatedObject(v, kTPPlayerKey);
            NSURL *url = [TPDownloader bestVideoURLNearView:v];
            if (!url) url = [TPDownloader bestURLFromVideoView:v player:player];
            NSDictionary *dash = [TPDownloader dashInfoFromVideoView:v player:player];
            if (!url && !dash) {
                if ([TPPrefs boolForKey:TPKeyDebugToast])
                    [TPDownloader showReport:[TPDownloader debugReportForVideoView:v player:player]];
                else
                    [TPHUD toast:TPL(@"No download link found. Play the video for a moment, then try again.")];
                return;
            }
            [TPDownloader downloadVideoURL:url dash:dash];
        } menuItems:nil];
        [host addSubview:b];
        objc_setAssociatedObject(host, kTPButtonKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        TPDebug(TPL(@"Download button added"));
    }
    b.hidden = NO;
    b.frame = CGRectMake(sz.width - d - 10, 10, d, d);
    if (host.subviews.lastObject != b) [host bringSubviewToFront:b];
}

%group Download

%hook _TtC11IGVideoView11IGVideoView

- (void)videoPlayerDidPrepare:(id)player { %orig; TPRememberPlayer(self, player); }
- (void)videoPlayerDidInitialPlay:(id)player { %orig; TPRememberPlayer(self, player); TPPauseIfHeld(player); }
- (void)videoPlayerDidReadyToDisplay:(id)player { %orig; TPRememberPlayer(self, player); }
- (void)videoPlayer:(id)player didLoadVideoInView:(id)view playbackReason:(long long)reason { %orig; TPRememberPlayer(self, player); }
- (void)videoPlayer:(id)player didUpdateLoadingProgress:(double)progress { %orig; TPRememberPlayer(self, player); }
- (void)videoPlayer:(id)player didUpdatePlaybackProgress:(double)progress { %orig; TPRememberPlayer(self, player); }

- (void)didMoveToWindow {
    %orig;
    TPEnsureVideoButton((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    TPEnsureVideoButton((UIView *)self);
}

%end

%end

// Batch download for a whole post (photos and videos).
static const void *kTPImgBtnKey   = &kTPImgBtnKey;
static const void *kTPBatchBtnKey = &kTPBatchBtnKey;

static void TPCollectImageViews(UIView *v, NSMutableArray<UIImageView *> *out, int depth) {
    if (v.hidden || v.alpha < 0.01 || depth > 30) return;
    if ([v isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)v;
        if (iv.image && iv.bounds.size.width >= 100 && iv.bounds.size.height >= 100) [out addObject:iv];
    }
    for (UIView *s in v.subviews) TPCollectImageViews(s, out, depth + 1);
}

static UIImageView *TPLargestImageView(UIView *host) {
    NSMutableArray<UIImageView *> *all = [NSMutableArray array];
    TPCollectImageViews(host, all, 0);
    UIImageView *best = nil;
    CGFloat bestArea = 0;
    for (UIImageView *iv in all) {
        CGFloat a = iv.bounds.size.width * iv.bounds.size.height;
        if (a > bestArea) { best = iv; bestArea = a; }
    }
    return best;
}

static NSURL *TPURLForImageView(UIImageView *iv) {
    id spec = [TPDownloader safeValue:iv key:@"imageSpecifier"];
    if (!spec) return nil;
    id imgURL = [TPDownloader ivarValue:spec name:@"_remoteImage_imageURL"];
    if (!imgURL) imgURL = [TPDownloader ivarValue:spec name:@"_prefetchedAdaptiveRemoteImageDEPRECATED_imageURL"];
    id u = [TPDownloader safeValue:imgURL key:@"url"];
    return [u isKindOfClass:[NSURL class]] ? u : nil;
}

static NSString *TPDedupeKey(NSURL *u) {
    return [[u.path lastPathComponent] stringByDeletingPathExtension];
}

static NSURL *TPVideoURLFromMedia(id media) {
    if (!media) return nil;
    for (NSString *key in @[@"video", @"computedVideo"]) {
        id video = [TPDownloader safeValue:media key:key];
        NSURL *u = [TPDownloader bestURLFromObject:video];
        if (u) return u;
    }
    return [TPDownloader bestURLFromObject:media];
}

static NSDictionary *TPVideoItem(NSURL *url, NSDictionary *dash) {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:dash ?: @{}];
    d[@"video"] = @YES;
    d[@"urls"] = url ? @[url] : @[];
    d[@"key"] = url ? TPDedupeKey(url) : [(NSURL *)dash[@"dashVideo"] absoluteString];
    return d;
}

static NSURL *TPImageURLFromMedia(id media) {
    if (!media) return nil;
    for (NSString *key in @[@"photo", @"computedPhoto"]) {
        id photo = [TPDownloader safeValue:media key:key];
        NSURL *best = TPBestImageURLFromPhoto(photo);
        if (best) return best;
        if (!photo || ![photo respondsToSelector:@selector(imageURLForWidth:)]) continue;

        double w = 4096;
        id sizeVal = [TPDownloader safeValue:photo key:@"size"];
        if ([sizeVal isKindOfClass:[NSValue class]]) {
            CGSize sz = [(NSValue *)sizeVal CGSizeValue];
            if (sz.width > 0) w = sz.width;
        }
        id imgURL = nil;
        @try { imgURL = [photo imageURLForWidth:w]; } @catch (__unused id e) {}
        id u = [imgURL isKindOfClass:[NSURL class]] ? imgURL : [TPDownloader safeValue:imgURL key:@"url"];
        if ([u isKindOfClass:[NSURL class]]) return u;
    }
    return nil;
}

static NSDictionary *TPItemForMediaCell(UIView *cell) {
    id fragment = [TPDownloader ivarValue:cell name:@"mediaFragment"];

    static Class videoCellClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ videoCellClass = NSClassFromString(@"_TtC16BCNFeedMediaCell21BCNFeedMediaVideoCell"); });
    UIView *vv = TPFindView(cell, TPVideoViewClass(), 30);
    BOOL isVideo = vv != nil || (videoCellClass && [cell isKindOfClass:videoCellClass]);

    if (isVideo) {
        NSURL *url = nil;
        NSDictionary *dash = nil;
        if (vv) {
            id player = objc_getAssociatedObject(vv, kTPPlayerKey);
            url = [TPDownloader bestURLFromVideoView:vv player:player];
            dash = [TPDownloader dashInfoFromVideoView:vv player:player];
        }
        if (!dash) dash = [TPDownloader dashInfoFromObject:fragment];
        if (!url) url = TPVideoURLFromMedia(fragment);
        if (!url && fragment) url = [TPDownloader bestVideoURLHarvestedFromObject:fragment];
        if (!url && !dash) {
            TPDebug([NSString stringWithFormat:@"video fragment: %@", fragment ? NSStringFromClass([fragment class]) : @"nil"]);
            return @{ @"video": @YES, @"failed": @YES };
        }
        return TPVideoItem(url, dash);
    }

    UIImageView *iv = TPLargestImageView(cell);
    NSURL *url = TPImageURLFromMedia(fragment);
    if (!url && iv) url = TPURLForImageView(iv);
    if (!url && fragment) url = [TPDownloader bestImageURLHarvestedFromObject:fragment];
    if (!url && !iv.image) {
        TPDebug([NSString stringWithFormat:@"photo fragment: %@", fragment ? NSStringFromClass([fragment class]) : @"nil"]);
        return nil;
    }

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"video"] = @NO;
    d[@"urls"] = url ? @[url] : @[];
    if (iv.image) d[@"image"] = iv.image;
    d[@"key"] = url ? TPDedupeKey(url) : [NSString stringWithFormat:@"img%p", iv.image];
    return d;
}

static NSDictionary *TPItemForMedia(id media) {
    if (!media) return nil;
    id video = [TPDownloader safeValue:media key:@"video"];
    if (!video) video = [TPDownloader safeValue:media key:@"computedVideo"];
    if (video) {
        NSURL *u = TPVideoURLFromMedia(media);
        if (!u) u = [TPDownloader bestVideoURLHarvestedFromObject:media];
        NSDictionary *dash = [TPDownloader dashInfoFromObject:media];
        if (!u && !dash) return @{ @"video": @YES, @"failed": @YES };
        return TPVideoItem(u, dash);
    }
    NSURL *u = TPImageURLFromMedia(media);
    if (!u) u = [TPDownloader bestImageURLHarvestedFromObject:media];
    if (!u) return @{ @"video": @NO, @"failed": @YES };
    return @{ @"video": @NO, @"urls": (u ? @[u] : @[]), @"key": TPDedupeKey(u) };
}

static NSString *gTPLastMediaDiag;

static void TPCollectMediaItemCells(UIView *v, NSMutableArray<UIView *> *out, int depth) {
    if (!v || depth > 12) return;
    if ([TPDownloader ivarValue:v name:@"mediaFragment"]) { [out addObject:v]; return; }
    for (UIView *s in v.subviews) TPCollectMediaItemCells(s, out, depth + 1);
}

static NSString *TPDescribeCount(id obj) {
    if (!obj) return @"nil";
    if ([obj respondsToSelector:@selector(count)]) return [NSString stringWithFormat:@"%lu", (unsigned long)[obj count]];
    return NSStringFromClass([obj class]);
}

static NSString *TPDiagForMedia(id media, NSInteger index) {
    id video = [TPDownloader safeValue:media key:@"video"] ?: [TPDownloader safeValue:media key:@"computedVideo"];
    NSData *dash = [TPDownloader safeValue:video key:@"dashManifestData"];
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"#%ld %@\n", (long)index + 1, media ? NSStringFromClass([media class]) : @"nil"];
    [r appendFormat:@"  video: %@\n", video ? NSStringFromClass([video class]) : @"nil"];
    [r appendFormat:@"  videoVersions: %@\n", TPDescribeCount([TPDownloader safeValue:video key:@"videoVersions"])];
    [r appendFormat:@"  allVideoURLs: %@\n", TPDescribeCount([TPDownloader safeValue:video key:@"allVideoURLs"])];
    [r appendFormat:@"  dash: %@\n", [dash isKindOfClass:[NSData class]] ? [NSString stringWithFormat:@"%lu bytes", (unsigned long)dash.length] : @"nil"];
    [r appendFormat:@"  photo: %@\n", [TPDownloader safeValue:media key:@"photo"] ? @"yes" : @"nil"];
    return r;
}

static NSArray<NSDictionary *> *TPCollectPostMediaFromModel(UIView *cellRoot) {
    NSMutableArray<UIView *> *itemCells = [NSMutableArray array];
    TPCollectMediaItemCells(cellRoot, itemCells, 0);
    UIView *itemCell = itemCells.firstObject;
    if (!itemCell) return nil;

    id frag   = [TPDownloader ivarValue:itemCell name:@"mediaFragment"];
    id parent = [TPDownloader ivarValue:itemCell name:@"parentMediaFragment"];
    if (!parent) parent = [TPDownloader safeValue:frag key:@"carouselParent"];

    NSArray *children = [TPDownloader safeValue:parent key:@"carouselMedia"];
    if (![children isKindOfClass:[NSArray class]] || !children.count) children = [TPDownloader safeValue:frag key:@"carouselMedia"];
    if (![children isKindOfClass:[NSArray class]] || !children.count) children = frag ? @[frag] : @[];

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableString *diag = [NSMutableString string];
    NSInteger idx = 0;
    for (id child in children) {
        NSDictionary *d = TPItemForMedia(child);

        if ([d[@"failed"] boolValue]) {
            for (UIView *c in itemCells) {
                if ([TPDownloader ivarValue:c name:@"mediaFragment"] != child) continue;
                NSDictionary *fromCell = TPItemForMediaCell(c);
                if (fromCell && ![fromCell[@"failed"] boolValue]) d = fromCell;
                break;
            }
        }
        if ([d[@"failed"] boolValue]) [diag appendString:TPDiagForMedia(child, idx)];
        idx++;

        if (!d) continue;
        NSString *key = d[@"key"];
        if (key) { if ([seen containsObject:key]) continue; [seen addObject:key]; }
        [items addObject:d];
    }
    gTPLastMediaDiag = diag.length
        ? [NSString stringWithFormat:@"ThreadsPulse %@\nparent: %@\nchildren: %lu\n\n%@",
           [TP_VERSION stringByAppendingString:@" [model]"], parent ? NSStringFromClass([parent class]) : @"nil", (unsigned long)children.count, diag]
        : nil;
    TPDebug([NSString stringWithFormat:TPL(@"Found %ld of %ld items"), (long)items.count, (long)children.count]);
    return items;
}

// Media is read from the carousel cell's `items` (BCNFeedMediaViewModel -> IGPhoto / IGVideo)
// rather than from visible cells, so items that are scrolled away or reused are still found.
// The view model's `kind` is a Swift enum; pointers and classes are validated before reading it.
static NSSet<NSValue *> *TPClassFamily(NSString *baseName) {
    Class base = NSClassFromString(baseName);
    if (!base) return [NSSet set];
    NSMutableSet<NSValue *> *set = [NSMutableSet set];
    unsigned int n = 0;
    Class *all = objc_copyClassList(&n);
    for (unsigned int i = 0; i < n; i++) {
        for (Class k = all[i]; k; k = class_getSuperclass(k)) {
            if (k == base) { [set addObject:[NSValue valueWithPointer:(__bridge const void *)all[i]]]; break; }
        }
    }
    free(all);
    return set;
}

static NSSet<NSValue *> *TPPhotoClasses(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = TPClassFamily(@"IGPhoto"); });
    return s;
}
static NSSet<NSValue *> *TPVideoClasses(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = TPClassFamily(@"IGVideo"); });
    return s;
}

static id TPObjectFromWord(uintptr_t w, NSSet<NSValue *> *allowed) {
    uintptr_t p = w & 0x0000000FFFFFFFF8ULL;
    if (p < 0x100000000ULL) return nil;
    if (!malloc_zone_from_ptr((const void *)p)) return nil;
    uintptr_t isa = *(const uintptr_t *)p & 0x0000000FFFFFFFF8ULL;
    if (![allowed containsObject:[NSValue valueWithPointer:(const void *)isa]]) return nil;
    return (__bridge id)(void *)p;
}

static uint8_t *TPIvarAddress(id obj, const char *name) {
    if (!obj) return NULL;
    for (Class c = object_getClass(obj); c; c = class_getSuperclass(c)) {
        Ivar iv = class_getInstanceVariable(c, name);
        if (iv) return (uint8_t *)(__bridge void *)obj + ivar_getOffset(iv);
    }
    return NULL;
}

static double TPNumber(id v) {
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}

static NSURL *TPBestImageURLFromPhoto(id photo) {
    if (!photo) return nil;
    NSURL *best = nil;
    double bestArea = -1;
    NSMutableArray<NSString *> *sizes = [NSMutableArray array];
    for (NSString *ivar in @[@"_originalImageVersions", @"_processedImageVersions"]) {
        NSArray *vers = [TPDownloader ivarValue:photo name:ivar];
        if (![vers isKindOfClass:[NSArray class]]) continue;
        for (id v in vers) {
            NSURL *u = [v isKindOfClass:[NSURL class]] ? v : [TPDownloader safeValue:v key:@"url"];
            if (![u isKindOfClass:[NSURL class]]) continue;
            double w = TPNumber([TPDownloader safeValue:v key:@"width"]);
            double h = TPNumber([TPDownloader safeValue:v key:@"height"]);
            if (w <= 0 || h <= 0) {
                id info = [TPDownloader safeValue:v key:@"imageURLInfo"];
                w = TPNumber([TPDownloader safeValue:info key:@"width"]);
                h = TPNumber([TPDownloader safeValue:info key:@"height"]);
            }
            double area = (w > 0 && h > 0) ? w * h : [TPDownloader imageAreaFromURL:u];
            if (area > bestArea) { best = u; bestArea = area; }
            if (gTPSizeLog) {
                [sizes addObject:(w > 0 ? [NSString stringWithFormat:@"%.0fx%.0f", w, h]
                                        : [NSString stringWithFormat:@"?(%@)", NSStringFromClass([v class])])];
            }
        }
    }
    if (gTPSizeLog && sizes.count) {
        [gTPSizeLog appendFormat:@"#%ld %@\n", (long)++gTPSizeIndex, [sizes componentsJoinedByString:@", "]];
    }
    return best;
}

static NSURL *TPImageURLFromPhoto(id photo) {
    NSURL *best = TPBestImageURLFromPhoto(photo);
    if (best) return best;
    if (!photo || ![photo respondsToSelector:@selector(imageURLForWidth:)]) return nil;
    double w = 4096;
    id sizeVal = [TPDownloader safeValue:photo key:@"size"];
    if ([sizeVal isKindOfClass:[NSValue class]]) {
        CGSize sz = [(NSValue *)sizeVal CGSizeValue];
        if (sz.width > 0) w = sz.width;
    }
    id imgURL = nil;
    @try { imgURL = [photo imageURLForWidth:w]; } @catch (__unused id e) {}
    id u = [imgURL isKindOfClass:[NSURL class]] ? imgURL : [TPDownloader safeValue:imgURL key:@"url"];
    return [u isKindOfClass:[NSURL class]] ? u : nil;
}

static NSString *TPDiagForVideo(id video, NSInteger index) {
    NSData *dash = [TPDownloader safeValue:video key:@"dashManifestData"];
    return [NSString stringWithFormat:@"#%ld video: %@\n  videoVersions: %@\n  allVideoURLs: %@\n  dash: %@\n",
            (long)index + 1, video ? NSStringFromClass([video class]) : @"nil",
            TPDescribeCount([TPDownloader safeValue:video key:@"videoVersions"]),
            TPDescribeCount([TPDownloader safeValue:video key:@"allVideoURLs"]),
            [dash isKindOfClass:[NSData class]] ? [NSString stringWithFormat:@"%lu bytes", (unsigned long)dash.length] : @"nil"];
}

static NSArray<NSDictionary *> *TPCollectPostMediaFromViewModels(UIView *cellRoot) {
    id vms = [TPDownloader ivarValue:cellRoot name:@"items"];
    if (![vms isKindOfClass:[NSArray class]] || ![(NSArray *)vms count]) return nil;

    NSMutableArray<UIView *> *itemCells = [NSMutableArray array];
    TPCollectMediaItemCells(cellRoot, itemCells, 0);

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableString *diag = [NSMutableString string];
    NSInteger idx = -1, recognized = 0;

    for (id vm in (NSArray *)vms) {
        idx++;
        uint8_t *kind = TPIvarAddress(vm, "kind");
        if (!kind) continue;
        uintptr_t w0 = ((uintptr_t *)kind)[0], w1 = ((uintptr_t *)kind)[1];
        id video = TPObjectFromWord(w0, TPVideoClasses()) ?: TPObjectFromWord(w1, TPVideoClasses());
        id photo = video ? nil : (TPObjectFromWord(w0, TPPhotoClasses()) ?: TPObjectFromWord(w1, TPPhotoClasses()));
        if (!video && !photo) continue;
        recognized++;

        NSDictionary *d = nil;
        if (video) {
            NSURL *u = [TPDownloader bestURLFromObject:video] ?: [TPDownloader bestVideoURLHarvestedFromObject:video];
            NSDictionary *dash = [TPDownloader dashInfoFromObject:video];
            if (!u && dash) {
                d = TPVideoItem(nil, dash);
            } else if (!u) {
                for (UIView *c in itemCells) {
                    uint8_t *mi = TPIvarAddress(c, "mediaIndex");
                    if (!mi || mi[8] != 0 || *(NSInteger *)mi != idx) continue;
                    NSDictionary *fromCell = TPItemForMediaCell(c);
                    if (fromCell && ![fromCell[@"failed"] boolValue]) d = fromCell;
                    break;
                }
                if (!d) { d = @{ @"video": @YES, @"failed": @YES }; [diag appendString:TPDiagForVideo(video, idx)]; }
            } else {
                d = TPVideoItem(u, dash);
            }
        } else {
            NSURL *u = TPImageURLFromPhoto(photo);
            d = u ? @{ @"video": @NO, @"urls": (u ? @[u] : @[]), @"key": TPDedupeKey(u) }
                  : @{ @"video": @NO, @"failed": @YES };
        }

        NSString *key = d[@"key"];
        if (key) { if ([seen containsObject:key]) continue; [seen addObject:key]; }
        [items addObject:d];
    }
    if (!recognized) return nil;

    gTPLastMediaDiag = diag.length
        ? [NSString stringWithFormat:@"ThreadsPulse %@ [items]\nitems: %lu\n\n%@", TP_VERSION, (unsigned long)[(NSArray *)vms count], diag]
        : nil;
    TPDebug([NSString stringWithFormat:TPL(@"Found %ld of %ld items"), (long)items.count, (long)[(NSArray *)vms count]]);
    return items;
}

static NSArray<NSDictionary *> *TPCollectPostMedia(UIView *cellRoot) {
    NSArray *items = TPCollectPostMediaFromViewModels(cellRoot);
    return items.count ? items : TPCollectPostMediaFromModel(cellRoot);
}

// Original-size photos: the app only receives resized versions, so the post page on
// threads.com is fetched and the largest candidate is matched by file name.
static NSString *TPShortcodeFromPK(NSString *pk) {
    pk = [[pk componentsSeparatedByString:@"_"] firstObject];
    unsigned long long n = strtoull(pk.UTF8String, NULL, 10);
    if (!n) return nil;
    static const char *alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    NSMutableString *s = [NSMutableString string];
    while (n) { [s insertString:[NSString stringWithFormat:@"%c", alpha[n % 64]] atIndex:0]; n /= 64; }
    return s;
}

static NSString *TPCodeFromMedia(id media) {
    if (!media) return nil;
    id code = [TPDownloader safeValue:media key:@"code"];
    if ([code isKindOfClass:[NSString class]] && [code length]) return code;
    return nil;
}

static NSString *TPPostCodeForCell(UIView *cellRoot) {
    NSMutableArray<UIView *> *itemCells = [NSMutableArray array];
    TPCollectMediaItemCells(cellRoot, itemCells, 0);
    for (UIView *c in itemCells) {
        id frag = [TPDownloader ivarValue:c name:@"mediaFragment"];
        id parent = [TPDownloader ivarValue:c name:@"parentMediaFragment"] ?: [TPDownloader safeValue:frag key:@"carouselParent"];
        NSString *code = TPCodeFromMedia(parent);
        if (code) return code;
        id parentId = [TPDownloader safeValue:frag key:@"carouselParentId"];
        if ([parentId isKindOfClass:[NSString class]] && [parentId length]) return TPShortcodeFromPK(parentId);
        if (!parent) { code = TPCodeFromMedia(frag); if (code) return code; }
    }

    UICollectionView *feed = nil;
    for (UIView *v = cellRoot.superview; v; v = v.superview) if ([v isKindOfClass:[UICollectionView class]]) { feed = (UICollectionView *)v; break; }
    if (feed && [cellRoot isKindOfClass:[UICollectionViewCell class]]) {
        NSIndexPath *ip = [feed indexPathForCell:(UICollectionViewCell *)cellRoot];
        for (UICollectionViewCell *c in feed.visibleCells) {
            if (!ip || [feed indexPathForCell:c].section != ip.section) continue;
            id m = [TPDownloader ivarValue:c name:@"cellMediaFragment"];
            NSString *code = TPCodeFromMedia(m);
            if (code) return code;
            id pk = [TPDownloader safeValue:m key:@"pk"];
            if ([pk isKindOfClass:[NSString class]] && [pk length]) return TPShortcodeFromPK(pk);
        }
    }

    id vms = [TPDownloader ivarValue:cellRoot name:@"items"];
    if ([vms isKindOfClass:[NSArray class]] && [(NSArray *)vms count] == 1) {
        uint8_t *kind = TPIvarAddress([(NSArray *)vms firstObject], "kind");
        if (kind) {
            uintptr_t w0 = ((uintptr_t *)kind)[0], w1 = ((uintptr_t *)kind)[1];
            id photo = TPObjectFromWord(w0, TPPhotoClasses()) ?: TPObjectFromWord(w1, TPPhotoClasses());
            id mid = [TPDownloader safeValue:photo key:@"mediaID"];
            if ([mid isKindOfClass:[NSString class]]) return TPShortcodeFromPK(mid);
        }
    }
    return nil;
}

static NSString *TPUnescapeJSONText(NSString *s) {
    for (int i = 0; i < 3; i++) {
        NSString *before = s;
        s = [s stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
        s = [s stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        s = [s stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"];
        s = [s stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
        if ([s isEqualToString:before]) break;
    }
    return [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

static NSString *TPHTMLSummary(NSString *html) {
    NSMutableString *r = [NSMutableString string];
    for (NSString *k in @[@"image_versions2", @"candidates", @"cdninstagram", @"fbcdn", @"og:image", @"\"width\"", @"login"]) {
        NSUInteger n = [html componentsSeparatedByString:k].count - 1;
        [r appendFormat:@"%@:%lu ", k, (unsigned long)n];
    }
    NSRange cdn = [html rangeOfString:@"cdninstagram"];
    if (cdn.location == NSNotFound) cdn = [html rangeOfString:@"fbcdn"];
    if (cdn.location != NSNotFound) {
        NSUInteger start = cdn.location > 160 ? cdn.location - 160 : 0;
        NSUInteger len = MIN((NSUInteger)360, html.length - start);
        NSString *snip = [[html substringWithRange:NSMakeRange(start, len)] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        [r appendFormat:@"\n  …%@…", snip];
    }
    return r;
}

static NSDictionary<NSString *, NSURL *> *TPOriginalsFromHTML(NSString *rawHTML, NSInteger *candidateCount, BOOL avatars) {
    NSString *html = TPUnescapeJSONText(rawHTML);
    NSMutableDictionary<NSString *, NSURL *> *best = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *area = [NSMutableDictionary dictionary];
    static NSRegularExpression *objRe, *wRe, *hRe, *uRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        objRe = [NSRegularExpression regularExpressionWithPattern:@"\\{[^{}]{0,2000}?\"url\":\"https:[^\"]+\"[^{}]{0,2000}?\\}" options:0 error:nil];
        wRe = [NSRegularExpression regularExpressionWithPattern:@"\"width\":(\\d+)" options:0 error:nil];
        hRe = [NSRegularExpression regularExpressionWithPattern:@"\"height\":(\\d+)" options:0 error:nil];
        uRe = [NSRegularExpression regularExpressionWithPattern:@"\"url\":\"(https:[^\"]+)\"" options:0 error:nil];
    });
    NSInteger count = 0;
    for (NSTextCheckingResult *m in [objRe matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *obj = [html substringWithRange:m.range];
        NSTextCheckingResult *w = [wRe firstMatchInString:obj options:0 range:NSMakeRange(0, obj.length)];
        NSTextCheckingResult *h = [hRe firstMatchInString:obj options:0 range:NSMakeRange(0, obj.length)];
        NSTextCheckingResult *u = [uRe firstMatchInString:obj options:0 range:NSMakeRange(0, obj.length)];
        if (!w || !h || !u) continue;
        NSString *raw = [obj substringWithRange:[u rangeAtIndex:1]];
        raw = [raw stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        raw = [raw stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"];
        raw = [raw stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        NSURL *url = [NSURL URLWithString:raw];
        if (!url) continue;
        NSString *path = url.path.lowercaseString;
        if ([path hasSuffix:@".mp4"]) continue;
        if ([path containsString:@"-19/"] != avatars) continue;
        double a = [[obj substringWithRange:[w rangeAtIndex:1]] doubleValue] * [[obj substringWithRange:[h rangeAtIndex:1]] doubleValue];
        count++;
        NSString *key = TPDedupeKey(url);
        if (a > [area[key] doubleValue]) { area[key] = @(a); best[key] = url; }
    }
    static NSRegularExpression *ogRe, *ogW, *ogH;
    static dispatch_once_t once2;
    dispatch_once(&once2, ^{
        ogRe = [NSRegularExpression regularExpressionWithPattern:@"<meta[^>]+property=\"og:image\"[^>]+content=\"([^\"]+)\"" options:NSRegularExpressionCaseInsensitive error:nil];
        ogW  = [NSRegularExpression regularExpressionWithPattern:@"property=\"og:image:width\"[^>]+content=\"(\\d+)\"" options:NSRegularExpressionCaseInsensitive error:nil];
        ogH  = [NSRegularExpression regularExpressionWithPattern:@"property=\"og:image:height\"[^>]+content=\"(\\d+)\"" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSTextCheckingResult *og = [ogRe firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (og) {
        NSURL *url = [NSURL URLWithString:[html substringWithRange:[og rangeAtIndex:1]]];
        if (url && [url.path.lowercaseString containsString:@"-19/"] == avatars) {
            NSTextCheckingResult *w = [ogW firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            NSTextCheckingResult *h = [ogH firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            double a = (w && h) ? [[html substringWithRange:[w rangeAtIndex:1]] doubleValue] * [[html substringWithRange:[h rangeAtIndex:1]] doubleValue] : 1;
            NSString *key = TPDedupeKey(url);
            count++;
            if (a > [area[key] doubleValue]) { area[key] = @(a); best[key] = url; }
        }
    }
    if (candidateCount) *candidateCount = count;
    return best;
}

static BOOL TPItemsHaveImage(NSArray<NSDictionary *> *items) {
    for (NSDictionary *d in items) if (![d[@"video"] boolValue]) return YES;
    return NO;
}

static void TPUpgradeFromPage(NSURL *page, BOOL avatars, NSString *label, NSString *hudTitle,
                              NSArray<NSDictionary *> *items, void (^done)(NSArray<NSDictionary *> *));

static void TPUpgradeToOriginals(NSString *code, NSArray<NSDictionary *> *items, void (^done)(NSArray<NSDictionary *> *)) {
    BOOL hasImage = TPItemsHaveImage(items);
    if (!hasImage) { done(items); return; }
    if (!code) {
        [TPDownloader appendPendingReport:@"[original] post code not found\n"];
        done(items);
        return;
    }
    NSURL *page = [NSURL URLWithString:[@"https://www.threads.com/t/" stringByAppendingString:code]];
    TPUpgradeFromPage(page, NO, [@"code " stringByAppendingString:code], TPL(@"Getting original photos…"), items, done);
}

static void TPUpgradeFromPage(NSURL *page, BOOL avatars, NSString *label, NSString *hudTitle,
                              NSArray<NSDictionary *> *items, void (^done)(NSArray<NSDictionary *> *)) {
    __block BOOL finished = NO;
    __block NSURLSessionDataTask *task = nil;
    TPHUD *hud = [TPHUD showWithTitle:hudTitle cancel:^{
        finished = YES;
        [task cancel];
    }];
    void (^finish)(NSArray *) = ^(NSArray *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished) return;
            finished = YES;
            [hud dismiss];
            done(result);
        });
    };

    NSArray<NSString *> *agents = @[
        @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
        @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
    ];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSMutableString *log = [NSMutableString string];

    __block void (^attempt)(NSUInteger) = nil;
    attempt = ^(NSUInteger idx) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:page cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
        [req setValue:agents[idx] forHTTPHeaderField:@"User-Agent"];
        [req setValue:@"text/html,application/xhtml+xml" forHTTPHeaderField:@"Accept"];
        [req setValue:@"zh-TW,zh;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];
        [req setValue:@"navigate" forHTTPHeaderField:@"Sec-Fetch-Mode"];
        task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (finished) { attempt = nil; return; }
            NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
            NSString *html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            NSInteger cands = 0;
            NSDictionary<NSString *, NSURL *> *originals = html ? TPOriginalsFromHTML(html, &cands, avatars) : @{};
            [log appendFormat:@"[original] %@ · HTTP %ld · %lu KB · candidates %ld%@\n",
                 idx == 0 ? @"desktop" : @"mobile", (long)status, (unsigned long)data.length / 1024, (long)cands,
                 err ? [@" · " stringByAppendingString:err.localizedDescription] : @""];
            if (html && !cands) [log appendFormat:@"  %@\n", TPHTMLSummary(html)];

            if (!originals.count && idx + 1 < agents.count) {
                attempt(idx + 1);
                return;
            }
            attempt = nil;

            NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
            NSInteger upgraded = 0, images = 0;
            for (NSDictionary *d in items) {
                if ([d[@"video"] boolValue]) { [out addObject:d]; continue; }
                images++;
                NSURL *orig = d[@"key"] ? originals[d[@"key"]] : nil;
                if (!orig && !avatars && originals.count == 1 && items.count == 1) orig = originals.allValues.firstObject;
                NSArray *urls = d[@"urls"];
                if (orig && ![urls containsObject:orig]) {
                    NSMutableDictionary *nd = [d mutableCopy];
                    nd[@"urls"] = [@[orig] arrayByAddingObjectsFromArray:urls ?: @[]];
                    [out addObject:nd];
                    upgraded++;
                } else {
                    [out addObject:d];
                }
            }
            [log appendFormat:@"[original] %@ · matched %ld/%ld\n", label, (long)upgraded, (long)images];
            [TPDownloader appendPendingReport:log];
            finish(out);
        }];
        [task resume];
    };
    attempt(0);
}

static void TPBatchDownload(UIView *cell, NSInteger filter) {
    BOOL debug = [TPPrefs boolForKey:TPKeyDebugToast];
    gTPSizeLog = debug ? [NSMutableString string] : nil;
    gTPSizeIndex = 0;
    NSArray<NSDictionary *> *raw = TPCollectPostMedia(cell);
    if (gTPSizeLog.length) [TPDownloader appendPendingReport:[@"[photo sizes in app]\n" stringByAppendingString:gTPSizeLog]];
    gTPSizeLog = nil;
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSInteger skipped = 0;
    for (NSDictionary *d in raw) {
        BOOL isVideo = [d[@"video"] boolValue];
        if (filter == 1 && isVideo) continue;
        if (filter == 2 && !isVideo) continue;
        if ([d[@"failed"] boolValue]) { skipped++; continue; }
        [items addObject:d];
    }
    if (skipped && gTPLastMediaDiag && [TPPrefs boolForKey:TPKeyDebugToast]) {
        [TPDownloader showReport:gTPLastMediaDiag];
        if (!items.count) return;
    }
    if (!items.count) {
        [TPHUD toast:skipped ? TPL(@"No download link found. Play the video for a moment, then try again.") : TPL(@"No media found")];
        return;
    }
    if (skipped) [TPHUD toast:[NSString stringWithFormat:TPL(@"%ld items skipped (no download link)"), (long)skipped]];
    if ([TPPrefs boolForKey:TPKeyOriginalImage]) {
        NSString *code = TPItemsHaveImage(items) ? TPPostCodeForCell(cell) : nil;
        TPUpgradeToOriginals(code, items, ^(NSArray<NSDictionary *> *upgraded) { [TPDownloader downloadItems:upgraded]; });
    } else {
        [TPDownloader downloadItems:items];
    }
}

static void TPEnsureBatchButton(UIView *cell) {
    UIButton *b = objc_getAssociatedObject(cell, kTPBatchBtnKey);
    CGSize sz = cell.bounds.size;
    BOOL want = cell.window && [TPPrefs boolForKey:TPKeyShowDownloadBtn] && sz.width >= 150 && sz.height >= 120;
    if (!want) { b.hidden = YES; return; }

    const CGFloat d = 38;
    if (!b) {
        __weak UIView *wc = cell;
        TPMenuItem *all  = [TPMenuItem itemWithTitle:TPL(@"Download All Media") symbol:@"square.and.arrow.down.on.square"
                                              handler:^{ if (wc) TPBatchDownload(wc, 0); }];
        TPMenuItem *imgs = [TPMenuItem itemWithTitle:TPL(@"Download Images Only") symbol:@"photo"
                                              handler:^{ if (wc) TPBatchDownload(wc, 1); }];
        TPMenuItem *vids = [TPMenuItem itemWithTitle:TPL(@"Download Videos Only") symbol:@"video"
                                              handler:^{ if (wc) TPBatchDownload(wc, 2); }];
        b = [TPUI circleButtonWithSymbol:@"arrow.down.to.line" diameter:d onTap:^{
            if (wc) TPBatchDownload(wc, 0);
        } menuItems:@[all, imgs, vids]];
        [cell addSubview:b];
        objc_setAssociatedObject(cell, kTPBatchBtnKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        TPDebug(TPL(@"Download button added"));
    }
    b.hidden = NO;

    UICollectionView *cv = (UICollectionView *)TPFindView(cell, [UICollectionView class], 7);
    CGRect r = cv ? [cell convertRect:cv.bounds fromView:cv] : cell.bounds;
    r = CGRectIntersection(r, cell.bounds);
    if (CGRectIsNull(r) || CGRectIsEmpty(r)) r = cell.bounds;
    b.frame = CGRectMake(CGRectGetMaxX(r) - d - 10, CGRectGetMinY(r) + 10, d, d);
    if (cell.subviews.lastObject != b) [cell bringSubviewToFront:b];
}

static NSSet<NSValue *> *TPMediaClasses(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = TPClassFamily(@"IGMedia"); });
    return s;
}

static NSString *TPPostCodeForLightbox(UIView *cell) {
    id item = [TPDownloader ivarValue:cell name:@"postItem"];
    if (item) {
        id parent = [TPDownloader safeValue:item key:@"carouselParent"];
        NSString *code = TPCodeFromMedia(parent);
        if (code) return code;
        id parentId = [TPDownloader safeValue:item key:@"carouselParentId"];
        if ([parentId isKindOfClass:[NSString class]] && [parentId length]) return TPShortcodeFromPK(parentId);
        id top = [TPDownloader safeValue:item key:@"topLevelPost"];
        code = TPCodeFromMedia(top);
        if (code) return code;
        if (!parent) { code = TPCodeFromMedia(item); if (code) return code; }
    }

    static Class lbClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lbClass = NSClassFromString(@"_TtC11BCNLightbox25BCNLightboxViewController"); });
    for (UIResponder *r = cell; r; r = r.nextResponder) {
        if (!lbClass || ![r isKindOfClass:lbClass]) continue;
        id content = [TPDownloader ivarValue:r name:@"content"];
        uint8_t *body = TPIvarAddress(content, "body");
        if (!body) break;
        for (int i = 0; i < 4; i++) {
            id media = TPObjectFromWord(((uintptr_t *)body)[i], TPMediaClasses());
            NSString *code = TPCodeFromMedia(media);
            if (code) return code;
        }
        break;
    }
    return nil;
}

static void TPDownloadLightboxImages(UIView *host, BOOL all) {
    NSMutableArray<UIImageView *> *ivs = [NSMutableArray array];
    if (all) {
        UIView *root = host;
        for (UIView *v = host.superview; v; v = v.superview) {
            if ([v isKindOfClass:[UIScrollView class]]) {
                UIScrollView *sv = (UIScrollView *)v;
                if (sv.contentSize.width > sv.bounds.size.width * 1.2) { root = sv; break; }
            }
        }
        NSMutableArray<UIImageView *> *found = [NSMutableArray array];
        TPCollectImageViews(root, found, 0);
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (UIImageView *iv in found) {
            NSURL *u = TPURLForImageView(iv);
            NSString *key = u ? TPDedupeKey(u) : [NSString stringWithFormat:@"%p", iv.image];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [ivs addObject:iv];
        }
        UIView *rootView = root;
        [ivs sortUsingComparator:^NSComparisonResult(UIImageView *a, UIImageView *b) {
            CGFloat ax = [rootView convertPoint:CGPointZero fromView:a].x, bx = [rootView convertPoint:CGPointZero fromView:b].x;
            return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
        }];
    } else {
        UIImageView *iv = TPLargestImageView(host);
        if (iv) [ivs addObject:iv];
    }

    NSURL *bestOfItem = nil;
    if (!all) bestOfItem = TPBestImageURLFromPhoto([TPDownloader safeValue:[TPDownloader ivarValue:host name:@"postItem"] key:@"photo"]);

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (UIImageView *iv in ivs) {
        NSURL *u = TPURLForImageView(iv);
        if (bestOfItem && (!u || [TPDedupeKey(u) isEqualToString:TPDedupeKey(bestOfItem)])) u = bestOfItem;
        if (!u && !iv.image) continue;
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[@"video"] = @NO;
        item[@"urls"] = u ? @[u] : @[];
        if (u) item[@"key"] = TPDedupeKey(u);
        if (iv.image) item[@"image"] = iv.image;
        [items addObject:item];
    }
    if (!items.count) { [TPHUD toast:TPL(@"No image found")]; return; }

    if ([TPPrefs boolForKey:TPKeyOriginalImage]) {
        TPUpgradeToOriginals(TPPostCodeForLightbox(host), items, ^(NSArray<NSDictionary *> *upgraded) {
            [TPDownloader downloadItems:upgraded];
        });
    } else {
        [TPDownloader downloadItems:items];
    }
}

static void TPEnsureLightboxButton(UIView *host) {
    UIButton *b = objc_getAssociatedObject(host, kTPImgBtnKey);
    CGSize sz = host.bounds.size;
    UIImageView *iv = nil;
    BOOL want = host.window && [TPPrefs boolForKey:TPKeyShowDownloadBtn] && sz.width >= 120 && sz.height >= 120;
    if (want) { iv = TPLargestImageView(host); want = (iv != nil); }
    if (!want) { b.hidden = YES; return; }

    const CGFloat d = 38;
    if (!b) {
        __weak UIView *wh = host;
        TPMenuItem *one = [TPMenuItem itemWithTitle:TPL(@"Download This Image") symbol:@"photo"
                                             handler:^{ if (wh) TPDownloadLightboxImages(wh, NO); }];
        TPMenuItem *all = [TPMenuItem itemWithTitle:TPL(@"Download All Images in Post") symbol:@"photo.on.rectangle.angled"
                                             handler:^{ if (wh) TPDownloadLightboxImages(wh, YES); }];
        b = [TPUI circleButtonWithSymbol:@"arrow.down.to.line" diameter:d onTap:^{
            if (wh) TPDownloadLightboxImages(wh, NO);
        } menuItems:@[one, all]];
        [host addSubview:b];
        objc_setAssociatedObject(host, kTPImgBtnKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    b.hidden = NO;
    CGRect r = CGRectIntersection([host convertRect:iv.bounds fromView:iv], host.bounds);
    b.frame = CGRectMake(CGRectGetMaxX(r) - d - 10, CGRectGetMaxY(r) - d - 10, d, d);
    if (host.subviews.lastObject != b) [host bringSubviewToFront:b];
}

%group Images

%hook _TtC16BCNFeedMediaCell16BCNFeedMediaCell
- (void)layoutSubviews { %orig; TPEnsureBatchButton((UIView *)self); }
- (void)didMoveToWindow { %orig; TPEnsureBatchButton((UIView *)self); }
%end

%hook _TtC11BCNLightbox20BCNLightboxPhotoCell
- (void)layoutSubviews { %orig; TPEnsureLightboxButton((UIView *)self); }
%end

%end

// Default playback speed. Threads resets the rate to 1.0 when a long-press 2x ends;
// that reset is redirected to the chosen speed.
static float TPSpeedForIndex(NSInteger i) {
    static const float table[] = {1.0f, 1.25f, 1.5f, 2.0f};
    return (i >= 0 && i <= 3) ? table[i] : 1.0f;
}

static const void *kTPPlayerInitKey = &kTPPlayerInitKey;

// Disable Autoplay.
// Simply refusing to play leaves the cell without its sound icon and playback UI. Instead,
// Threads is allowed to start (reason 1 = scrolled into view), the underlying FNFPlayer plays
// muted until the first frame and pauses, and later play calls are ignored. A tap (a touch
// that barely moved) releases the hold. Other reasons, such as full screen, play normally.
static const void *kTPUserStartedKey = &kTPUserStartedKey;
static const void *kTPTouchStartKey  = &kTPTouchStartKey;
static const void *kTPHeldKey = &kTPHeldKey;
static CFAbsoluteTime gTPLastTapAt = 0;

static id TPFNFPlayer(id inner) {
    Ivar iv = class_getInstanceVariable(object_getClass(inner), "_player");
    return iv ? object_getIvar(inner, iv) : nil;
}

static const void *kTPPrimedKey = &kTPPrimedKey;

static void TPSetHeld(id inner, BOOL held) {
    id v = held ? @YES : nil;
    objc_setAssociatedObject(inner, kTPHeldKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id fnf = TPFNFPlayer(inner);
    if (!fnf) return;
    objc_setAssociatedObject(fnf, kTPHeldKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!held && objc_getAssociatedObject(fnf, kTPPrimedKey)) {
        objc_setAssociatedObject(fnf, kTPPrimedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([fnf respondsToSelector:@selector(setVolume:rampTime:)]) [fnf setVolume:1.0f rampTime:0];
    }
}

static void TPPauseIfHeld(id player) {
    id inner = TPInnerPlayer(player);
    if (!inner || !objc_getAssociatedObject(inner, kTPHeldKey)) return;
    id fnf = TPFNFPlayer(inner);
    if ([fnf respondsToSelector:@selector(pause)]) [fnf pause];
}

static BOOL TPPlayerMayPlay(id player, long long reason) {
    if (![TPPrefs boolForKey:TPKeyNoAutoplay]) return YES;
    if (objc_getAssociatedObject(player, kTPUserStartedKey)) return YES;
    UIView *view = ((TPWeakBox *)objc_getAssociatedObject(player, kTPPlayerViewKey)).object;
    BOOL tapped = CFAbsoluteTimeGetCurrent() - gTPLastTapAt < 1.5;
    BOOL inFeed = !view || TPInsideFeedMediaCell(view);
    if (reason != 1 || tapped || !inFeed) {
        objc_setAssociatedObject(player, kTPUserStartedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (reason != 1) TPDebug([NSString stringWithFormat:@"%@ (%lld)", TPL(@"Playback allowed"), reason]);
        return YES;
    }
    TPDebug([NSString stringWithFormat:@"%@ (%lld)", TPL(@"Autoplay blocked"), reason]);
    return NO;
}

static void TPPlayVideoAtTouch(UITouch *t) {
    UIView *hit = t.view;
    Class vcls = TPVideoViewClass();
    if (!hit || !vcls) return;
    UIView *video = nil;
    for (UIView *v = hit; v; v = v.superview) if ([v isKindOfClass:vcls]) { video = v; break; }
    if (!video) {
        UIView *cell = hit;
        Class cellCls = TPFeedMediaCellClass();
        while (cell && !(cellCls && [cell isKindOfClass:cellCls])) cell = cell.superview;
        if (cell) video = TPFindView(cell, vcls, 30);
    }
    if (!video) return;
    id player = TPInnerPlayer(objc_getAssociatedObject(video, kTPPlayerKey));
    if (!player) { TPDebug(TPL(@"Tap: no video player found")); return; }
    objc_setAssociatedObject(player, kTPUserStartedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!objc_getAssociatedObject(player, kTPHeldKey)) return;
    TPSetHeld(player, NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id fnf = TPFNFPlayer(player);
        if (![fnf respondsToSelector:@selector(play)]) { TPDebug(TPL(@"Tap: no video player found")); return; }
        TPDebug(TPL(@"Tap: replaying video"));
        [fnf play];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![player respondsToSelector:@selector(isPlaying)]) return;
            TPDebug(TPL([(id)player isPlaying] ? @"Tap: video is playing" : @"Tap: video still not playing"));
        });
    });
}

%group VideoSettings

%hook IGFNFVideoPlayer

- (void)playWithReason:(long long)reason callsiteContext:(id)context {
    BOOL may = TPPlayerMayPlay(self, reason);
    if ([TPPrefs boolForKey:TPKeyNoAutoplay]) TPSetHeld(self, !may);
    if (!objc_getAssociatedObject(self, kTPPlayerInitKey)) {
        objc_setAssociatedObject(self, kTPPlayerInitKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        float sp = TPSpeedForIndex([TPPrefs integerForKey:TPKeyPlaySpeed]);
        if (sp != 1.0f) [(id)self setPlaybackSpeed:sp];
    }
    %orig;
}

- (void)stopWithReason:(long long)reason callsiteContext:(id)context {
    objc_setAssociatedObject(self, kTPUserStartedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(self, kTPHeldKey)) TPSetHeld(self, NO);
    %orig;
}

- (void)setPlaybackSpeed:(float)speed {
    float def = TPSpeedForIndex([TPPrefs integerForKey:TPKeyPlaySpeed]);
    if (def != 1.0f && speed == 1.0f) speed = def;
    %orig(speed);
}

%end

static BOOL TPFNFShouldSkipPlay(id fnf) {
    if (!objc_getAssociatedObject(fnf, kTPHeldKey)) return NO;
    if (objc_getAssociatedObject(fnf, kTPPrimedKey)) return YES;
    objc_setAssociatedObject(fnf, kTPPrimedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([fnf respondsToSelector:@selector(setVolume:rampTime:)]) [fnf setVolume:0 rampTime:0];
    return NO;
}

%hook FNFPlayer
- (void)play {
    if (TPFNFShouldSkipPlay(self)) return;
    %orig;
}
- (void)playWithContext:(id)context {
    if (TPFNFShouldSkipPlay(self)) return;
    %orig;
}
%end

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches && [TPPrefs boolForKey:TPKeyNoAutoplay]) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseBegan) {
                CGPoint p = [t locationInView:nil];
                objc_setAssociatedObject(t, kTPTouchStartKey,
                    @[@(p.x), @(p.y), @(CFAbsoluteTimeGetCurrent())], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else if (t.phase == UITouchPhaseEnded) {
                NSArray *s = objc_getAssociatedObject(t, kTPTouchStartKey);
                if (s.count == 3) {
                    CGPoint p = [t locationInView:nil];
                    CGFloat dx = p.x - [s[0] doubleValue], dy = p.y - [s[1] doubleValue];
                    if (dx * dx + dy * dy < 15 * 15 && CFAbsoluteTimeGetCurrent() - [s[2] doubleValue] < 0.6) {
                        gTPLastTapAt = CFAbsoluteTimeGetCurrent();
                        TPPlayVideoAtTouch(t);
                    }
                }
            }
        }
    }
    %orig;
}
%end

%end

// Exact post times: Threads builds "3h" style labels through NSDate's relative-date category,
// so those methods return absolute dates instead.
static NSString *TPExactString(NSDate *date) {
    NSInteger mode = [TPPrefs integerForKey:TPKeyExactTime];
    if (mode == 0 || ![date isKindOfClass:[NSDate class]]) return nil;
    static NSDateFormatter *shortF, *fullF;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shortF = [NSDateFormatter new];
        shortF.locale = NSLocale.autoupdatingCurrentLocale;
        [shortF setLocalizedDateFormatFromTemplate:@"MMMd HHmm"];
        fullF = [NSDateFormatter new];
        fullF.locale = NSLocale.autoupdatingCurrentLocale;
        [fullF setLocalizedDateFormatFromTemplate:@"yMMMd HHmmss"];
    });
    return [(mode == 1 ? shortF : fullF) stringFromDate:date];
}

%group Time

%hook NSDate
- (id)formattedDateRelativeToNow {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNow {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)partiallyShortenedFormattedDateRelativeToNow {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNowIncludeYears {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNowWithOptions:(unsigned long long)o {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)partiallyShortenedFormattedDateRelativeToNowHideSeconds:(BOOL)s options:(unsigned long long)o {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNowWithFloorDaysWeeks:(BOOL)w {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)formattedDateRelativeToNowHideSeconds:(BOOL)s {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)formattedDateRelativeToNowHideSeconds:(BOOL)s shouldFloorDaysWeeks:(BOOL)w {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNowHideSeconds:(BOOL)s {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNowHideSeconds:(BOOL)s shouldFloorDaysWeeks:(BOOL)w {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNowHideSeconds:(BOOL)s shouldFloorDaysWeeks:(BOOL)w options:(unsigned long long)o {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)shortenedFormattedDateRelativeToNowHideSeconds:(BOOL)s shouldFloorDaysWeeks:(BOOL)w includeYears:(BOOL)y options:(unsigned long long)o {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)formattedDateRelativeToNowIncludingYearsHideSeconds:(BOOL)s {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
- (id)formattedDateRelativeToNowIncludingYearsHideSeconds:(BOOL)s shouldFloorDaysWeeks:(BOOL)w {
    NSString *e = TPExactString((NSDate *)self);
    return e ?: %orig;
}
%end

%end

// Like Confirmation. The UFI row is the Swift BCNUFIButton, but taps reach it through an ObjC
// target-action, so they can be intercepted. Its `type` is a payload-free enum stored in one
// byte: comment = 0, repost = 1, like = 2. `toggledState` is YES when already liked, and
// unliking is never confirmed.
static void TPConfirm(NSString *title, NSString *actionTitle, void (^go)(void)) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:TPL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *x) { if (go) go(); }];
    [a addAction:ok];
    a.preferredAction = ok;
    [TPTopViewController() presentViewController:a animated:YES completion:nil];
}

%group Interactions

%hook _TtC6BCNUFI12BCNUFIButton
- (void)didEndTappingButtonOnPurpose:(id)sender {
    if (![TPPrefs boolForKey:TPKeyConfirmLike]) { %orig; return; }
    uint8_t *type = TPIvarAddress(self, "type");
    uint8_t *toggled = TPIvarAddress(self, "toggledState");
    BOOL isLike = type && *type == 2;
    BOOL alreadyLiked = toggled && *toggled != 0;
    if (!isLike || alreadyLiked) { %orig; return; }
    TPDebug(TPL(@"Like confirmation shown"));
    TPConfirm(TPL(@"Like this post?"), TPL(@"Like"), ^{ %orig; });
}
%end

%end

static const void *kTPAvatarBtnKey = &kTPAvatarBtnKey;

static NSURL *TPURLFromImageSpecifier(id spec) {
    if (!spec) return nil;
    id imgURL = [TPDownloader ivarValue:spec name:@"_remoteImage_imageURL"];
    if (!imgURL) imgURL = [TPDownloader ivarValue:spec name:@"_prefetchedAdaptiveRemoteImageDEPRECATED_imageURL"];
    id u = [TPDownloader safeValue:imgURL key:@"url"];
    return [u isKindOfClass:[NSURL class]] ? u : nil;
}

static NSURL *TPURLFromString(id s) {
    if ([s isKindOfClass:[NSURL class]]) return s;
    if ([s isKindOfClass:[NSString class]] && [s length]) return [NSURL URLWithString:s];
    return nil;
}

static void TPDownloadAvatarFromPictureView(UIView *pic);

static void TPDownloadAvatar(UIViewController *vc) {
    TPDownloadAvatarFromPictureView([TPDownloader ivarValue:vc name:@"profilePictureView"]);
}

static void TPDownloadAvatarFromPictureView(UIView *pic) {
    id profileImage = [TPDownloader safeValue:pic key:@"image"];
    id user = [TPDownloader ivarValue:profileImage name:@"_profileImageModel_user"];

    NSURL *hd = nil;
    for (NSString *frag in @[@"asIGUserHDProfilePicURLFragment", @"asIGUserHDProfilePicImageURLFragment"]) {
        id info = [TPDownloader safeValue:[TPDownloader safeValue:user key:frag] key:@"hdProfilePicUrlInfo"];
        hd = TPURLFromString([TPDownloader safeValue:info key:@"urlString"]);
        if (hd) break;
    }
    NSURL *shown = TPURLFromImageSpecifier([TPDownloader ivarValue:profileImage name:@"_imageSpecifier"]);
    id derived = [TPDownloader safeValue:user key:@"asIGUserDerivedProfilePicURLFragment"];
    NSURL *normal = TPURLFromString([TPDownloader safeValue:derived key:@"computedProfilePicURLString"])
                 ?: TPURLFromString([TPDownloader safeValue:derived key:@"profilePicURLString"]);

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSURL *u in @[hd ?: (id)NSNull.null, shown ?: (id)NSNull.null, normal ?: (id)NSNull.null]) {
        if ([u isKindOfClass:[NSURL class]] && ![urls containsObject:u]) [urls addObject:u];
    }
    UIImageView *shownView = pic ? TPLargestImageView(pic) : nil;
    if (!urls.count && !shownView.image) { [TPHUD toast:TPL(@"No image found")]; return; }

    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    item[@"video"] = @NO;
    item[@"urls"] = urls;
    if (urls.firstObject) item[@"key"] = TPDedupeKey(urls.firstObject);
    if (shownView.image) item[@"image"] = shownView.image;

    id username = [TPDownloader safeValue:user key:@"username"];
    [TPDownloader appendPendingReport:[NSString stringWithFormat:@"[avatar] @%@ · hd %@ · shown %@\n",
                                       username ?: @"?", hd ? @"yes" : @"no", shown ? @"yes" : @"no"]];

    if ([TPPrefs boolForKey:TPKeyOriginalAvatar] && [username isKindOfClass:[NSString class]] && [username length] && item[@"key"]) {
        NSURL *page = [NSURL URLWithString:[@"https://www.threads.com/@" stringByAppendingString:username]];
        TPUpgradeFromPage(page, YES, [@"@" stringByAppendingString:username], TPL(@"Getting original photo…"), @[item],
                          ^(NSArray<NSDictionary *> *upgraded) { [TPDownloader downloadItems:upgraded]; });
    } else {
        [TPDownloader downloadItems:@[item]];
    }
}

static void TPEnsureAvatarButton(UIViewController *vc) {
    UIView *host = vc.view;
    if (!host.window) return;
    UIButton *b = objc_getAssociatedObject(vc, kTPAvatarBtnKey);
    if (![TPPrefs boolForKey:TPKeyShowDownloadBtn]) { b.hidden = YES; return; }

    const CGFloat d = 46;
    if (!b) {
        __weak UIViewController *wvc = vc;
        b = [TPUI circleButtonWithSymbol:@"arrow.down.to.line" diameter:d onTap:^{
            if (wvc) TPDownloadAvatar(wvc);
        } menuItems:nil];
        b.accessibilityLabel = TPL(@"Save Profile Picture");
        [host addSubview:b];
        objc_setAssociatedObject(vc, kTPAvatarBtnKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    b.hidden = NO;
    CGRect bounds = host.bounds;
    b.frame = CGRectMake(CGRectGetMaxX(bounds) - d - 24,
                         CGRectGetMaxY(bounds) - host.safeAreaInsets.bottom - d - 28, d, d);
    if (host.subviews.lastObject != b) [host bringSubviewToFront:b];
}

// Copy Profile Info: long-press gestures on the profile picture, name, username and bio.
// When the feature is off the gestures refuse to begin, so Threads' own long-presses still work.
static const void *kTPProfilePressKey = &kTPProfilePressKey;
static Class gTPProfileHeaderClass;

static UIView *TPProfileHeaderFor(UIView *v) {
    for (; v; v = v.superview) if (gTPProfileHeaderClass && [v isKindOfClass:gTPProfileHeaderClass]) return v;
    return nil;
}

static NSString *TPStyledText(id styled) {
    id attr = [TPDownloader safeValue:styled key:@"attributedString"];
    return [attr isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)attr string] : nil;
}

static NSString *TPTrimmed(NSString *s) {
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length ? s : nil;
}

static NSString *TPProfileName(UIView *header) {
    UILabel *l = [TPDownloader ivarValue:header name:@"fullNameLabel"];
    return [l isKindOfClass:[UILabel class]] ? TPTrimmed(l.text) : nil;
}

static NSString *TPProfileUsername(UIView *header) {
    UILabel *l = [TPDownloader ivarValue:header name:@"usernameLabel"];
    NSString *u = [l isKindOfClass:[UILabel class]] ? TPTrimmed(l.text) : nil;
    return [u hasPrefix:@"@"] ? [u substringFromIndex:1] : u;
}

static NSString *TPProfileBio(UIView *header) {
    UIView *bio = TPFindView(header, objc_getClass("IGProfileBioView"), 8);
    if (!bio) return nil;
    NSString *t = TPTrimmed(TPStyledText([TPDownloader ivarValue:bio name:@"_fullCollapsibleBioString"]));
    if (!t) t = TPTrimmed(TPStyledText([TPDownloader ivarValue:bio name:@"_stringForView"]));
    if (!t) {
        id c = [TPDownloader safeValue:bio key:@"contentString"];
        t = TPTrimmed([c isKindOfClass:[NSString class]] ? c : TPStyledText(c));
    }
    return t;
}

static void TPCopyText(NSString *text) {
    UIPasteboard.generalPasteboard.string = text;
    [TPUI hapticLight];
    [TPHUD toast:TPL(@"Copied")];
}

@interface TPProfilePressHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)pressed:(UILongPressGestureRecognizer *)g;
@end

@implementation TPProfilePressHandler
+ (instancetype)shared {
    static TPProfilePressHandler *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [TPProfilePressHandler new]; });
    return h;
}

static void TPAddSheetAction(UIAlertController *sheet, NSString *title, NSString *symbol, void (^handler)(void)) {
    UIAlertAction *a = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *x) { handler(); }];
    @try { [a setValue:[UIImage systemImageNamed:symbol] forKey:@"image"]; } @catch (__unused id e) {}
    [sheet addAction:a];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    UIView *header = TPProfileHeaderFor(g.view);
    BOOL isPicture = [g.view isEqual:[TPDownloader ivarValue:header name:@"profilePictureView"]];
    return [TPPrefs boolForKey:TPKeyCopyProfile] || (isPicture && [TPPrefs boolForKey:TPKeyShowDownloadBtn]);
}

- (void)pressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIView *src = g.view;
    UIView *header = TPProfileHeaderFor(src);
    BOOL isPicture = [src isEqual:[TPDownloader ivarValue:header name:@"profilePictureView"]];
    BOOL canSave = isPicture && [TPPrefs boolForKey:TPKeyShowDownloadBtn];
    BOOL canCopy = [TPPrefs boolForKey:TPKeyCopyProfile];
    NSString *name = canCopy ? TPProfileName(header) : nil;
    NSString *username = canCopy ? TPProfileUsername(header) : nil;
    NSString *bio = canCopy ? TPProfileBio(header) : nil;
    if (!canSave && !name && !username && !bio) return;

    [TPUI hapticLight];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIView *wsrc = src;
    if (canSave) TPAddSheetAction(sheet, TPL(@"Save Profile Picture"), @"arrow.down.to.line", ^{ if (wsrc) TPDownloadAvatarFromPictureView(wsrc); });
    if (name)     TPAddSheetAction(sheet, TPL(@"Copy Name"), @"person.text.rectangle", ^{ TPCopyText(name); });
    if (username) TPAddSheetAction(sheet, TPL(@"Copy Username"), @"at", ^{ TPCopyText(username); });
    if (bio)      TPAddSheetAction(sheet, TPL(@"Copy Bio"), @"text.quote", ^{ TPCopyText(bio); });
    [sheet addAction:[UIAlertAction actionWithTitle:TPL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = src;
    sheet.popoverPresentationController.sourceRect = src.bounds;
    [TPTopViewController() presentViewController:sheet animated:YES completion:nil];
}
@end

static void TPAddProfilePress(UIView *v, BOOL takeOverExisting) {
    if (![v isKindOfClass:[UIView class]] || objc_getAssociatedObject(v, kTPProfilePressKey)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:[TPProfilePressHandler shared]
                                                                                    action:@selector(pressed:)];
    g.minimumPressDuration = 0.45;
    g.delegate = [TPProfilePressHandler shared];
    if (takeOverExisting) {
        for (UIGestureRecognizer *other in v.gestureRecognizers)
            if ([other isKindOfClass:[UILongPressGestureRecognizer class]]) [other requireGestureRecognizerToFail:g];
    }
    v.userInteractionEnabled = YES;
    [v addGestureRecognizer:g];
    objc_setAssociatedObject(v, kTPProfilePressKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void TPEnsureProfilePress(UIView *header) {
    TPAddProfilePress([TPDownloader ivarValue:header name:@"profilePictureView"], NO);
    if (![TPPrefs boolForKey:TPKeyCopyProfile]) return;
    TPAddProfilePress([TPDownloader ivarValue:header name:@"usernameLabel"], NO);
    TPAddProfilePress([TPDownloader ivarValue:header name:@"fullNameLabel"], NO);
    TPAddProfilePress(TPFindView(header, objc_getClass("IGProfileBioView"), 8), YES);
}

%group Avatar

%hook _TtC17BCNProfilePicture41BCNProfilePictureFullscreenViewController
- (void)viewDidLayoutSubviews {
    %orig;
    TPEnsureAvatarButton((UIViewController *)self);
}
%end

%hook _TtC10BCNProfile20BCNProfileHeaderView
- (void)layoutSubviews {
    %orig;
    TPEnsureProfilePress((UIView *)self);
}
%end

%end

// Ways to open the settings: the Pulse button in Threads' settings, a three-finger long-press,
// and a long-press on the Home tab.
static const void *kTPGestureKey3 = &kTPGestureKey3;

// The three-finger gesture recognizes alongside everything else. Once it begins, the other
// recognizers on the same touches are disabled and re-enabled, which cancels them; otherwise
// lifting the fingers would also trigger whatever button was touched first.
@interface TPThreeFingerHelper : NSObject <UIGestureRecognizerDelegate>
@end

@implementation TPThreeFingerHelper {
    NSHashTable<UITouch *> *_touches;
}
+ (instancetype)shared {
    static TPThreeFingerHelper *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [self new]; });
    return h;
}
- (instancetype)init {
    if ((self = [super init])) _touches = [NSHashTable weakObjectsHashTable];
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    for (UITouch *t in _touches.allObjects)
        if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) [_touches removeObject:t];
    [_touches addObject:touch];
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (void)cancelOtherGesturesExcept:(UIGestureRecognizer *)mine {
    for (UITouch *t in _touches.allObjects) {
        for (UIGestureRecognizer *g in t.gestureRecognizers) {
            if (g == mine || !g.enabled) continue;
            g.enabled = NO;
            g.enabled = YES;
        }
    }
    [_touches removeAllObjects];
}
@end

%group Menu

static NSString *const kTPEntryID = @"ThreadsPulseEntry";

static void TPTintEntryButton(UIButton *b) {
    if (![b isKindOfClass:[UIButton class]] || !b.configuration) return;
    UIButtonConfiguration *cfg = b.configuration;
    cfg.baseForegroundColor = [TPUI accentIcon];
    b.configuration = cfg;
}

%hook _TtC11BCNSettings25BCNSettingsViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    NSMutableArray *items = [vc.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    for (UIBarButtonItem *i in items) if ([i.customView.accessibilityIdentifier isEqualToString:kTPEntryID]) {
        TPTintEntryButton((UIButton *)i.customView);
        return;
    }

    UIColor *tint = [TPUI accentIcon];
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.title = @"Pulse";
    cfg.image = [UIImage systemImageNamed:@"waveform.path.ecg"
                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
    cfg.imagePadding = 4;
    cfg.baseForegroundColor = tint;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(4, 4, 4, 0);
    cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *a) {
        NSMutableDictionary *m = [a mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        return m;
    };
    __weak UIViewController *wvc = vc;
    UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
        if (wvc) [TPSettingsViewController present];
    }]];
    b.accessibilityIdentifier = kTPEntryID;
    b.accessibilityLabel = @"ThreadsPulse";
    [b sizeToFit];
    __weak UIButton *wb = b;
    [[NSNotificationCenter defaultCenter] addObserverForName:TPThemeDidChangeNotification object:nil
                                                       queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        if (wb) TPTintEntryButton(wb);
    }];
    [items addObject:[[UIBarButtonItem alloc] initWithCustomView:b]];
    vc.navigationItem.rightBarButtonItems = items;
}
%end

%hook UIWindow

- (void)becomeKeyWindow {
    %orig;
    if (!objc_getAssociatedObject(self, kTPGestureKey3)) {
        UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tp_threeFingerLongPress:)];
        g.numberOfTouchesRequired = 3;
        g.minimumPressDuration = 1.0;
        g.cancelsTouchesInView = YES;
        g.delegate = [TPThreeFingerHelper shared];
        [(UIWindow *)self addGestureRecognizer:g];
        objc_setAssociatedObject(self, kTPGestureKey3, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%new
- (void)tp_threeFingerLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [[TPThreeFingerHelper shared] cancelOtherGesturesExcept:g];
    [TPUI hapticLight];
    [TPSettingsViewController present];
}

%end

%end

// Copied-link detection. detectPatternsForPatterns: only reports whether the clipboard holds a
// URL, so no paste prompt appears until the user taps Open (or chose Auto-open). The link is
// handed to Threads as an NSUserActivity so Threads routes it itself.
static BOOL TPIsThreadsURL(NSURL *u) {
    NSString *host = u.host.lowercaseString;
    if (![u.scheme.lowercaseString hasPrefix:@"http"]) return NO;
    BOOL threads = [host isEqualToString:@"threads.com"] || [host hasSuffix:@".threads.com"] ||
                   [host isEqualToString:@"threads.net"] || [host hasSuffix:@".threads.net"];
    return threads && u.path.length > 1;
}

static void TPOpenInThreads(NSURL *url) {
    NSUserActivity *act = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    act.webpageURL = url;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        id<UISceneDelegate> d = scene.delegate;
        if ([d respondsToSelector:@selector(scene:continueUserActivity:)]) {
            [d scene:scene continueUserActivity:act];
            TPDebug(TPL(@"Opened link from clipboard"));
            return;
        }
    }
    id<UIApplicationDelegate> ad = UIApplication.sharedApplication.delegate;
    if ([ad respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)]) {
        [ad application:UIApplication.sharedApplication continueUserActivity:act restorationHandler:^(NSArray *r) {}];
        return;
    }
    [UIApplication.sharedApplication openURL:url options:@{ UIApplicationOpenURLOptionUniversalLinksOnly: @YES } completionHandler:nil];
}

static void TPOpenClipboardLinkSilently(BOOL silent);
static void TPOpenClipboardLink(void) { TPOpenClipboardLinkSilently(NO); }

static void TPOpenClipboardLinkSilently(BOOL silent) {
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSURL *url = pb.hasURLs ? pb.URL : nil;
    if (!TPIsThreadsURL(url)) {
        url = nil;
        NSString *text = pb.hasStrings ? pb.string : nil;
        if (text.length) {
            NSDataDetector *det = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
            for (NSTextCheckingResult *m in [det matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
                if (TPIsThreadsURL(m.URL)) { url = m.URL; break; }
            }
        }
    }
    if (!url) { if (!silent) [TPHUD toast:TPL(@"The copied link isn't a Threads link")]; return; }
    TPOpenInThreads([TPURLCleaner cleanURL:url]);
}

static void TPCheckClipboardForced(BOOL force) {
    if (![TPPrefs boolForKey:TPKeyClipboardLinks]) return;
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSInteger cc = pb.changeCount;
    if (!force) {
        if (cc == gTPOwnPasteboardChange) return;
        if (cc == [TPPrefs integerForKey:@"tp_clip_last_change"]) return;
    }
    [TPPrefs setInteger:cc forKey:@"tp_clip_last_change"];

    NSSet *patterns = [NSSet setWithObject:UIPasteboardDetectionPatternProbableWebURL];
    [pb detectPatternsForPatterns:patterns completionHandler:^(NSSet *found, NSError *err) {
        if (![found containsObject:UIPasteboardDetectionPatternProbableWebURL]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([TPPrefs integerForKey:TPKeyClipboardMode] == 1) {
                TPOpenClipboardLinkSilently(YES);
                return;
            }
            [TPHUD bannerWithText:TPL(@"Link copied") symbol:@"link" action:TPL(@"Open")
                         position:[TPPrefs integerForKey:TPKeyBannerPosition]
                          handler:^{ TPOpenClipboardLink(); }];
        });
    }];
}

static void TPCheckClipboard(void) { TPCheckClipboardForced(NO); }

static void TPScheduleClipboardCheckAfterSwitch(void) {
    static NSUInteger generation = 0;
    NSUInteger mine = ++generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != generation) return;
        TPDebug(TPL(@"Account switched"));
        TPCheckClipboardForced(YES);
    });
}

%group AccountSwitch

%hook IGAccountSwitcher
- (long long)switchToUser:(id)user destinationAppSurface:(id)surface destinationURL:(id)url entryPoint:(long long)point loggingData:(id)data {
    long long r = %orig;
    TPScheduleClipboardCheckAfterSwitch();
    return r;
}
- (long long)switchToUserWithPK:(id)pk destinationAppSurface:(id)surface destinationURL:(id)url entryPoint:(long long)point loggingData:(id)data {
    long long r = %orig;
    TPScheduleClipboardCheckAfterSwitch();
    return r;
}
- (void)recreateViewHierarchyForCurrentUserWithDestinationAppSurface:(id)surface {
    %orig;
    TPScheduleClipboardCheckAfterSwitch();
}
%end

%end

// Keep Feed Position. Coming back from the background, Threads decides how long the app was
// away from three places: IGWarmStartListener's applicationWillWarmStartWithTimeInterval...
// (home feed and BCNAppViewController), the feed's own lastBgTime, and the server thresholds
// in IGFeedRefreshInstructionsStore. Within the keep time all three report a short absence.
// Pull to refresh and cold launches are unaffected.
static CFAbsoluteTime gTPBackgroundedAt = 0;

static double TPKeepFeedLimitSeconds(void) {
    switch ([TPPrefs integerForKey:TPKeyKeepFeedLimit]) {
        case 0:  return 10 * 60;
        case 1:  return 30 * 60;
        default: return 0;
    }
}

static BOOL TPShouldKeepFeed(void) {
    static CFAbsoluteTime decidedAt = 0;
    static BOOL decided = NO;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - decidedAt < 10.0) return decided;

    BOOL keep = NO;
    if ([TPPrefs boolForKey:TPKeyKeepFeed] && gTPBackgroundedAt > 0) {
        double limit = TPKeepFeedLimitSeconds();
        keep = (limit == 0 || now - gTPBackgroundedAt < limit);
    }
    decidedAt = now;
    decided = keep;
    if (keep) TPDebug(TPL(@"Feed position kept"));
    return keep;
}

static void TPSetOptionalDateNow(id obj, const char *name) {
    Class cls = object_getClass(obj);
    Ivar iv = class_getInstanceVariable(cls, name);
    if (!iv) return;
    ptrdiff_t off = ivar_getOffset(iv);
    ptrdiff_t next = (ptrdiff_t)class_getInstanceSize(cls);
    unsigned int n = 0;
    Ivar *list = class_copyIvarList(cls, &n);
    for (unsigned int i = 0; i < n; i++) {
        ptrdiff_t o = ivar_getOffset(list[i]);
        if (o > off && o < next) next = o;
    }
    free(list);
    if (next - off < 9) return;
    uint8_t *p = (uint8_t *)(__bridge void *)obj + off;
    double t = CFAbsoluteTimeGetCurrent();
    memcpy(p, &t, sizeof(double));
    p[8] = 0;
}

static NSNumber *TPKeepFeedThreshold(NSNumber *orig) {
    if (![TPPrefs boolForKey:TPKeyKeepFeed]) return orig;
    double limit = TPKeepFeedLimitSeconds();
    if (limit == 0) return @(1.0e9);
    return (orig && orig.doubleValue >= limit) ? orig : @(limit);
}

%group KeepFeed

%hook _TtC11BCNMainFeed25BCNMainFeedViewController
- (void)applicationWillWarmStartWithTimeIntervalSinceBackgrounded:(double)backgrounded {
    %orig(TPShouldKeepFeed() ? 0.0 : backgrounded);
}
- (void)willEnterForeground {
    if (TPShouldKeepFeed()) TPSetOptionalDateNow(self, "lastBgTime");
    %orig;
}
%end

%hook BCNAppViewController
- (void)applicationWillWarmStartWithTimeIntervalSinceBackgrounded:(double)backgrounded {
    %orig(TPShouldKeepFeed() ? 0.0 : backgrounded);
}
%end

%hook _TtC30IGFeedRefreshInstructionsStore30IGFeedRefreshInstructionsStore
- (NSNumber *)warmStartRefreshInterval                   { return TPKeepFeedThreshold(%orig); }
- (NSNumber *)warmStartRefreshIntervalOnPeak             { return TPKeepFeedThreshold(%orig); }
- (NSNumber *)minimumWarmStartBackgroundedInterval       { return TPKeepFeedThreshold(%orig); }
- (NSNumber *)minimumWarmStartBackgroundedIntervalOnPeak { return TPKeepFeedThreshold(%orig); }
%end

%end

// Home tab taps: Threads scrolls to top when the feed is scrolled down, and refreshes when it
// is already at the top.
// - New tab bar (BCNLucentTabBarCoordinator): the decision happens in ObjC methods, so the tap
//   is simply not passed on.
// - Legacy tab bar (BCNLegacyTabBarController): the decision is in Swift and can't be reached.
//   The tap time is recorded and upward scrolls / refreshes of the feed are blocked for 1 s.
//   These fallback hooks are only installed the first time the legacy tab bar is tapped.
static Class gTPMainFeedClass;
static __weak UIViewController *gTPMainFeedVC;

static CGFloat TPTopOffset(UIScrollView *sv) { return -sv.adjustedContentInset.top; }

static BOOL TPIsMainFeedScrollView(UIScrollView *sv) {
    if (!gTPMainFeedClass) return NO;
    for (UIResponder *r = sv.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:[UIViewController class]]) return [r isKindOfClass:gTPMainFeedClass];
    }
    return NO;
}

static UIScrollView *TPVisibleMainFeedScrollView(void) {
    UIViewController *vc = gTPMainFeedVC;
    if (!vc || !vc.isViewLoaded || !vc.view.window) return nil;
    UIScrollView *best = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:vc.view];
    while (queue.count) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:[UICollectionView class]] && TPIsMainFeedScrollView((UIScrollView *)v)
            && (!best || v.bounds.size.height > best.bounds.size.height)) best = (UIScrollView *)v;
        [queue addObjectsFromArray:v.subviews];
    }
    return best;
}

static BOOL TPShouldBlockHomeReselect(void) {
    BOOL noTop = [TPPrefs boolForKey:TPKeyTabNoScrollTop], noRefresh = [TPPrefs boolForKey:TPKeyTabNoRefresh];
    if (!noTop && !noRefresh) return NO;
    UIScrollView *sv = TPVisibleMainFeedScrollView();
    if (!sv) return NO;
    BOOL atTop = sv.contentOffset.y <= TPTopOffset(sv) + 1.0;
    if (!atTop && noTop)    { TPDebug(TPL(@"Scroll to top blocked"));    return YES; }
    if (atTop && noRefresh) { TPDebug(TPL(@"Home tab refresh blocked")); return YES; }
    return NO;
}

static id TPSelectedTab(id controller) {
    SEL sel = sel_registerName("selectedTab");
    return [controller respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(controller, sel) : nil;
}

static CFAbsoluteTime gTPTabTapAt = 0;

static BOOL TPInTabTapWindow(void) {
    return gTPTabTapAt > 0 && CFAbsoluteTimeGetCurrent() - gTPTabTapAt < 1.0;
}

static BOOL TPShouldBlockFeedScroll(UIScrollView *sv, CGFloat targetY) {
    if (!TPInTabTapWindow() || sv.isTracking) return NO;
    if (targetY >= sv.contentOffset.y - 0.5) return NO;
    if (!TPIsMainFeedScrollView(sv)) return NO;
    BOOL atTop = sv.contentOffset.y <= TPTopOffset(sv) + 1.0;
    if ((!atTop && [TPPrefs boolForKey:TPKeyTabNoScrollTop]) || (atTop && [TPPrefs boolForKey:TPKeyTabNoRefresh])) {
        TPDebug(TPL(atTop ? @"Home tab refresh blocked" : @"Scroll to top blocked"));
        gTPTabTapAt = CFAbsoluteTimeGetCurrent();
        return YES;
    }
    return NO;
}

static BOOL TPShouldBlockTabRefresh(void) {
    if (!TPInTabTapWindow() || ![TPPrefs boolForKey:TPKeyTabNoRefresh]) return NO;
    TPDebug(TPL(@"Home tab refresh blocked"));
    return YES;
}

%group LegacyTabFallback

%hook _TtC11BCNMainFeed25BCNMainFeedViewController
- (void)didRequestedFeedRefresh {
    if (TPShouldBlockTabRefresh()) return;
    %orig;
}
%end

%hook IGRefreshControl
- (void)startLoadingAnimated:(BOOL)animated {
    if (TPShouldBlockTabRefresh()) return;
    %orig;
}
%end

%hook UIScrollView
- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    if (TPInTabTapWindow() && TPShouldBlockFeedScroll((UIScrollView *)self, offset.y)) return;
    %orig;
}
- (void)setContentOffset:(CGPoint)offset {
    if (TPInTabTapWindow() && TPShouldBlockFeedScroll((UIScrollView *)self, offset.y)) return;
    %orig;
}
- (void)setBounds:(CGRect)bounds {
    if (TPInTabTapWindow() && bounds.origin.y != ((UIScrollView *)self).bounds.origin.y
        && TPShouldBlockFeedScroll((UIScrollView *)self, bounds.origin.y)) return;
    %orig;
}
- (void)scrollRectToVisible:(CGRect)rect animated:(BOOL)animated {
    if (TPInTabTapWindow() && TPShouldBlockFeedScroll((UIScrollView *)self, rect.origin.y)) return;
    %orig;
}
%end

%hook UICollectionView
- (void)scrollToItemAtIndexPath:(NSIndexPath *)ip atScrollPosition:(UICollectionViewScrollPosition)pos animated:(BOOL)animated {
    if (TPInTabTapWindow() && ip.section == 0 && ip.item == 0
        && TPShouldBlockFeedScroll((UIScrollView *)self, -CGFLOAT_MAX)) return;
    %orig;
}
%end

%end

static void TPMarkLegacyTabTap(void) {
    if (![TPPrefs boolForKey:TPKeyTabNoScrollTop] && ![TPPrefs boolForKey:TPKeyTabNoRefresh]) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ %init(LegacyTabFallback); });
    gTPTabTapAt = CFAbsoluteTimeGetCurrent();
}

static CFAbsoluteTime gTPSuppressTabSelectUntil = 0;
static BOOL TPTabSelectSuppressed(void) { return CFAbsoluteTimeGetCurrent() < gTPSuppressTabSelectUntil; }

%group HomeFeedControls

%hook _TtC21BCNRootViewController25BCNLegacyTabBarController
- (void)didTapTabBarButton:(id)button       { TPMarkLegacyTabTap(); %orig; }
- (void)didDoubleTapTabBarButton:(id)button { TPMarkLegacyTabTap(); %orig; }
%end

%hook _TtC26BCNLucentTabBarCoordinator26BCNLucentTabBarCoordinator
- (BOOL)tabBarController:(id)controller shouldSelectTab:(id)tab {
    if (TPTabSelectSuppressed()) return NO;
    if (tab && tab == TPSelectedTab(controller) && TPShouldBlockHomeReselect()) return NO;
    return %orig;
}
- (void)tabBarController:(id)controller didSelectTab:(id)tab previousTab:(id)prev {
    if (tab && tab == prev && (TPTabSelectSuppressed() || TPShouldBlockHomeReselect())) return;
    %orig;
}
- (void)handleTabBarDoubleTap:(id)tap {
    if (TPTabSelectSuppressed() || TPShouldBlockHomeReselect()) return;
    %orig;
}
%end

%hook _TtC11BCNMainFeed25BCNMainFeedViewController
- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if ([TPPrefs boolForKey:TPKeyNoPullRefresh] && [sv isKindOfClass:[UIScrollView class]]
        && (sv.isTracking || sv.isDragging || sv.isDecelerating)) {
        CGFloat top = TPTopOffset(sv);
        if (sv.contentOffset.y < top) {
            sv.contentOffset = CGPointMake(sv.contentOffset.x, top);
            TPDebug(TPL(@"Pull to refresh blocked"));
        }
    }
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gTPMainFeedVC = (UIViewController *)self;
}
%end

%end

// The follow-suggestion sheet is BCNUserRecommendationsViewController. Only the presented
// (sheet) form is blocked; the same controller pushed from a profile still opens.
static Class gTPUserRecsClass;

static BOOL TPTreeContainsUserRecs(UIViewController *vc, int depth) {
    if (!vc || !gTPUserRecsClass || depth > 4) return NO;
    if ([vc isKindOfClass:gTPUserRecsClass]) return YES;
    if ([vc isKindOfClass:[UINavigationController class]])
        for (UIViewController *c in ((UINavigationController *)vc).viewControllers) if (TPTreeContainsUserRecs(c, depth + 1)) return YES;
    for (UIViewController *c in vc.childViewControllers) if (TPTreeContainsUserRecs(c, depth + 1)) return YES;
    return NO;
}

%group HideFollowSuggest

%hook UIViewController
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([TPPrefs boolForKey:TPKeyHideFollowSuggest] && TPTreeContainsUserRecs(vc, 0)) {
        TPDebug(TPL(@"Follow suggestions hidden"));
        return;
    }
    %orig;
}
%end

%hook _TtC22BCNUserRecommendations36BCNUserRecommendationsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (![TPPrefs boolForKey:TPKeyHideFollowSuggest]) return;
    UIViewController *me = (UIViewController *)self;
    UIViewController *top = me;
    while (top.parentViewController) top = top.parentViewController;
    if (!top.presentingViewController) return;
    TPDebug(TPL(@"Follow suggestions hidden"));
    dispatch_async(dispatch_get_main_queue(), ^{ [top dismissViewControllerAnimated:NO completion:nil]; });
}
%end

%end

// The new tab bar slides away based on the distance accumulated in scrollViewDidScroll: and
// scrollViewDidEndScrolling:. Those calls are withheld from the coordinator. The native iOS 26
// tab bar's minimize behavior is also set to never.
%group PinTabBar

%hook _TtC26BCNLucentTabBarCoordinator26BCNLucentTabBarCoordinator
- (void)scrollViewDidScroll:(id)scroll {
    if ([TPPrefs boolForKey:TPKeyPinTabBar]) return;
    %orig;
}
- (void)scrollViewDidEndScrolling:(id)scrolling {
    if ([TPPrefs boolForKey:TPKeyPinTabBar]) return;
    %orig;
}
%end

%hook _TtC26BCNLucentTabBarCoordinator31BCNLucentNativeTabBarController
- (void)viewIsAppearing:(BOOL)appearing {
    %orig;
    SEL sel = sel_registerName("setTabBarMinimizeBehavior:");
    if ([TPPrefs boolForKey:TPKeyPinTabBar] && [(id)self respondsToSelector:sel])
        ((void (*)(id, SEL, NSInteger))objc_msgSend)((id)self, sel, 1);
}
%end

%end

// Suggestions are IGListKit sections; returning 0 items hides a section without leaving a gap.
// BCNAYMFSectionController ("Suggested for you") is split by its `placement`:
// 0 home feed, 1 activity, 2 search, 3 profile chaining, 4 / 5 communities.
// 0 and 3 follow Suggested Accounts, 2 follows Search Suggestions, the rest are left alone.
// BCNSuggestedUser is only hidden for surface 1 (shown after following someone).
%group HideFeedSuggestions

%hook _TtC26BCNVerticalsSuggestionUnit43BCNVerticalsSuggestionUnitSectionController
- (long long)numberOfItems { return [TPPrefs boolForKey:TPKeyHideFeedSuggest] ? 0 : %orig; }
%end

%hook _TtC11BCNAYMFUnit24BCNAYMFSectionController
- (long long)numberOfItems {
    if ([TPPrefs boolForKey:TPKeyHideFeedSuggest]) {
        uint8_t *placement = TPIvarAddress(self, "placement");
        if (placement && (*placement == 0 || *placement == 3)) return 0;
    }
    if ([TPPrefs boolForKey:TPKeyHideSearchSuggest]) {
        uint8_t *placement = TPIvarAddress(self, "placement");
        if (placement && *placement == 2) return 0;
    }
    return %orig;
}
%end

%hook _TtC28BCNInterestFeedSuggestedUnit45BCNInterestFeedSuggestedUnitSectionController
- (long long)numberOfItems { return [TPPrefs boolForKey:TPKeyHideFeedSuggest] ? 0 : %orig; }
%end

%hook _TtC16BCNSuggestedUser33BCNSuggestedUserSectionController
- (long long)numberOfItems {
    if ([TPPrefs boolForKey:TPKeyHideFeedSuggest]) {
        uint8_t *surface = TPIvarAddress(self, "surface");
        if (surface && *surface == 1) return 0;
    }
    return %orig;
}
%end

%hook _TtC10BCNProfile20BCNProfileHeaderView
- (CGSize)sizeThatFits:(CGSize)fits {
    if ([TPPrefs boolForKey:TPKeyHideFeedSuggest]) {
        uint8_t *show = TPIvarAddress(self, "showProfileChain");
        if (show) *show = 0;
    }
    return %orig;
}
- (void)layoutSubviews {
    if ([TPPrefs boolForKey:TPKeyHideFeedSuggest]) {
        uint8_t *show = TPIvarAddress(self, "showProfileChain");
        if (show) *show = 0;
    }
    %orig;
}
%end

%hook _TtC18BCNProfileChaining22BCNProfileChainingView
- (CGSize)sizeThatFits:(CGSize)fits {
    if ([TPPrefs boolForKey:TPKeyHideFeedSuggest]) return CGSizeMake(fits.width, 0);
    return %orig;
}
- (void)layoutSubviews {
    %orig;
    ((UIView *)self).hidden = [TPPrefs boolForKey:TPKeyHideFeedSuggest];
}
%end

// "Are you interested in this post?" appears as a row under a post and as a batched section.
%hook _TtC29BCNFeedItemSeeMoreSeeLessCell29BCNFeedItemSeeMoreSeeLessCell
- (CGSize)sizeThatFits:(CGSize)fits {
    if ([TPPrefs boolForKey:TPKeyHidePostFeedback]) return CGSizeMake(fits.width, 0);
    return %orig;
}
- (void)layoutSubviews {
    %orig;
    ((UIView *)self).hidden = [TPPrefs boolForKey:TPKeyHidePostFeedback];
}
%end

%hook _TtC39BCNFeedBatchedSeeMoreSeeLessSessionUnit56BCNFeedBatchedSeeMoreSeeLessSessionUnitSectionController
- (long long)numberOfItems { return [TPPrefs boolForKey:TPKeyHidePostFeedback] ? 0 : %orig; }
%end

%end

// Threads learns about screenshots and screen recordings through IGScreenshotObserver.
%group BlockScreenshotDetection

%hook IGScreenshotObserver
- (void)_onTakenScreenshot {
    if ([TPPrefs boolForKey:TPKeyBlockScreenshotDetect]) { TPDebug(TPL(@"Screenshot detection blocked")); return; }
    %orig;
}
- (void)_screenCaptureStateDidChange:(id)change {
    if ([TPPrefs boolForKey:TPKeyBlockScreenshotDetect]) return;
    %orig;
}
%end

%end

// Block Analytics. Usage events are collected by FBAnalyticsCoreLogger and uploaded by
// IGAnalyticsNetworkConfigurator. New events are dropped at collection, and anything already
// stored is uploaded through Meta's own FBAnalyticsNoOpNetworkConfigurator, which sends nothing.
// Normal API traffic (login, posting, loading the feed) does not use this path.
static int gTPAnalyticsDropped;

static NSMutableDictionary<NSString *, NSNumber *> *gTPAnaCounts;
static NSMutableDictionary<NSString *, NSDictionary *> *gTPAnaLast;
static NSUInteger gTPAnaTotal;
static const NSUInteger kTPAnaRecentMax = 10;

// Analytics Log. Only names are counted for every event; the latest event object of each kind
// is kept and its payload is only read when the log is opened. Nothing is written to disk.
static void TPRecordAnalytics(id event, BOOL blocked) {
    if (!event) return;
    NSString *name = nil;
    @try { if ([event respondsToSelector:@selector(eventName)]) name = [event performSelector:@selector(eventName)]; } @catch (__unused id e) {}
    if (![name isKindOfClass:[NSString class]] || !name.length) name = @"(unnamed)";
    @synchronized ([TPPrefs class]) {
        if (!gTPAnaCounts) { gTPAnaCounts = [NSMutableDictionary new]; gTPAnaLast = [NSMutableDictionary new]; }
        gTPAnaTotal++;
        gTPAnaCounts[name] = @(gTPAnaCounts[name].unsignedIntegerValue + 1);
        if (gTPAnaLast[name] || gTPAnaLast.count < 100)
            gTPAnaLast[name] = @{ @"t": [NSDate date], @"n": name, @"e": event, @"b": @(blocked) };
    }
}

static NSString *TPAnaPayloadString(id event) {
    id payload = nil;
    @try { if ([event respondsToSelector:@selector(eventPayload)]) payload = [event performSelector:@selector(eventPayload)]; } @catch (__unused id e) {}
    if (!payload) return @"{}";
    NSString *s = nil;
    if ([NSJSONSerialization isValidJSONObject:payload]) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:nil];
        if (d) s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    if (!s) s = [payload description];
    if (s.length > 600) s = [[s substringToIndex:600] stringByAppendingString:@"…"];
    return s;
}

// Plain-language descriptions, observed from real Threads traffic. Unknown names fall back to a
// word-by-word translation, which is skipped when more than half the words are unknown.
static NSDictionary<NSString *, NSArray<NSString *> *> *TPAnaKnownEvents(void) {
    static NSDictionary *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = @{
        @"navigation":                       @[@"切換頁面", @"Page navigation"],
        @"time_spent_bit_array":             @[@"使用時長（逐秒記錄）", @"Time spent (per second)"],
        @"time_spent":                       @[@"使用時長", @"Time spent"],
        @"app_state":                        @[@"App 前景／背景切換", @"App foreground/background"],
        @"perf":                             @[@"效能紀錄（圖片、影片、動態的載入速度與網路狀況）", @"Performance (load times of images, videos, feed, and network)"],
        @"client_event":                     @[@"一般操作紀錄", @"General client event"],
        @"impression":                       @[@"內容出現在畫面上", @"Content shown on screen"],
        @"vpv":                              @[@"內容在畫面上停留的時間", @"How long content stayed on screen"],
        @"video_should_start":               @[@"影片準備播放", @"Video about to play"],
        @"video_started_playing":            @[@"影片開始播放", @"Video started"],
        @"video_paused":                     @[@"影片暫停", @"Video paused"],
        @"video_exited":                     @[@"離開影片", @"Left video"],
        @"video_displayed":                  @[@"影片出現在畫面上", @"Video shown on screen"],
        @"qe_exposure":                      @[@"實驗分組紀錄（你被分到哪個測試版本）", @"Experiment exposure (which test group you're in)"],
        @"ig_qe_exposure":                   @[@"實驗分組紀錄（你被分到哪個測試版本）", @"Experiment exposure (which test group you're in)"],
        @"gk_exposure":                      @[@"功能開關檢查紀錄", @"Feature gate check"],
        @"mobile_network_stats":             @[@"網路連線品質", @"Network quality"],
        @"cold_start":                       @[@"App 冷啟動速度", @"App cold start time"],
        @"warm_start":                       @[@"App 熱啟動速度", @"App warm start time"],
        @"memory_warning":                   @[@"記憶體不足警告", @"Low memory warning"],
        @"push_notification_received":       @[@"收到推播通知", @"Push notification received"],
        @"notification_open":                @[@"點開通知", @"Notification opened"],
        @"search":                           @[@"搜尋", @"Search"],
        @"like":                             @[@"按讚", @"Like"],
        @"unlike":                           @[@"收回讚", @"Unlike"],
        @"follow_button_tapped":             @[@"點了追蹤按鈕", @"Follow button tapped"],
        @"mobile_config_exposure_log":       @[@"伺服器設定值讀取紀錄（記錄 App 套用了哪些遠端設定）", @"Remote config exposure (which server settings the app used)"],
        @"mobile_config_param_access_without_exposure": @[@"伺服器設定值讀取（未分組）", @"Remote config read (no exposure)"],
        @"privacy_flow_trigger_event":       @[@"隱私相關流程觸發紀錄", @"Privacy flow triggered"],
        @"ig_time_spent_action":             @[@"使用時長（依操作記錄）", @"Time spent (by action)"],
        @"ig_time_spent_screen_time":        @[@"使用時長（各畫面停留時間）", @"Time spent (per screen)"],
        @"instagram_ad_delivery":            @[@"廣告投放紀錄", @"Ad delivery"],
        @"enigma_ios_event":                 @[@"廣告成效追蹤", @"Ad performance tracking"],
        @"odin_features":                    @[@"裝置與使用狀態數值（網路、啟動方式等，用於預測與推薦）", @"Device and usage signals (network, launch type, used for prediction)"],
        @"app_installations":                @[@"已安裝的 Meta App（是否裝了 Instagram、Facebook 等）", @"Installed Meta apps (Instagram, Facebook, etc.)"],
        @"badging_event":                    @[@"通知紅點／數字標記", @"Notification badge"],
        @"push_notification_setting":        @[@"推播通知設定狀態", @"Push notification settings"],
        @"instagram_organic_impression":    @[@"一般串文（非廣告）出現在畫面上", @"Regular (non-ad) post shown on screen"],
        @"instagram_organic_vpvd_imp":      @[@"一般串文在畫面上停留的時間", @"How long a regular post stayed on screen"],
        @"threads_media_header_context_impression": @[@"串文上方的話題標籤（例如相關熱門話題）出現在畫面上", @"Topic label above a post (e.g. related trend) shown"],
        @"client_registration_initiated":   @[@"App 向伺服器登記裝置", @"App registering the device with the server"],
        @"fx_upsells_product":              @[@"帳號管理中心的跨 App 推廣（例如連結 Instagram、Facebook）", @"Accounts Center cross-app promotion (e.g. linking Instagram, Facebook)"],
        @"instagram_two_measurement_debugging_signal": @[@"串文曝光追蹤訊號（含追蹤碼與串文編號）", @"Post impression tracking signal (tracking token, post ID)"],
        @"media_playback_compound":         @[@"影片播放過程紀錄（準備、開始、暫停、緩衝等）", @"Video playback log (prepare, start, pause, buffering)"],
        @"media_playback_compound_fast":    @[@"影片播放過程紀錄（即時版）", @"Video playback log (real-time)"],
        @"barcelona_permalink_action":      @[@"串文頁的操作（進入、離開、看到哪裡）", @"Post page actions (enter, exit, how far you read)"],
        @"barcelona_media_viewer_entry":    @[@"進入全螢幕檢視圖片或影片", @"Opened full-screen media viewer"],
        @"barcelona_media_viewer_exit":     @[@"離開全螢幕檢視圖片或影片", @"Closed full-screen media viewer"],
        @"barcelona_post_tap":              @[@"點擊串文", @"Tapped a post"],
        @"client_registration_request_sent": @[@"裝置登記：請求已送出", @"Device registration: request sent"],
        @"client_registration_response_received": @[@"裝置登記：收到回應", @"Device registration: response received"],
        @"client_registration_failure":     @[@"裝置登記失敗", @"Device registration failed"],
        @"client_registration_token_obtained_from_provider": @[@"裝置登記：從系統取得推播權杖", @"Device registration: push token obtained"],
        @"instagram_media_metrics":         @[@"圖片與影片的載入、顯示數據", @"Media load and display metrics"],
        @"instagram_client_delivery_funnel_start": @[@"動態內容載入流程開始（這次送來哪些串文）", @"Feed delivery started (which posts were served)"],
        @"instagram_client_delivery_funnel_end": @[@"動態內容載入流程結束", @"Feed delivery finished"],
        @"bcn_press_location_event":        @[@"點擊位置紀錄（點了畫面哪裡）", @"Tap location (where on screen you tapped)"],
        @"ads_tracking_status":             @[@"廣告追蹤授權狀態（iOS「允許 App 要求追蹤」）", @"Ad tracking permission (iOS App Tracking Transparency)"],
        @"apple_ad_services_token":         @[@"Apple 廣告歸因權杖（是否透過廣告安裝 Threads）", @"Apple ad attribution token (whether you installed via an ad)"],
        @"fx_access_library":               @[@"帳號管理中心存取紀錄", @"Accounts Center access"],
        @"threads_recommended_entity_impression": @[@"推薦內容（例如相關標籤）出現在畫面上", @"Recommended item (e.g. related tags) shown"],
        @"threads_badge_click":             @[@"點擊通知紅點", @"Tapped a notification badge"],
        @"save_sso_nonce_key_chain_success": @[@"登入憑證已存入鑰匙圈", @"Login token saved to Keychain"],
        @"cats_device_identifiers_reliability_ig": @[@"裝置識別碼一致性檢查", @"Device identifier consistency check"],
        @"instagram_device_ids":            @[@"裝置識別碼回報", @"Device identifiers"],
        @"appjobs_ios_job_finished":        @[@"背景工作完成", @"Background job finished"],
        @"screen_time_service_init":        @[@"使用時長統計服務啟動", @"Screen time tracking started"],
        @"device_permissions_external":     @[@"系統權限狀態（相機、相簿、定位等）", @"System permissions (camera, photos, location, etc.)"],
        @"threads_author_badge_impression": @[@"作者旁的標章（例如認證徽章）出現在畫面上", @"Author badge (e.g. verified) shown"],
        @"instagram_organic_carousel_vpvd_imp": @[@"多圖串文在畫面上停留的時間", @"How long a multi-photo post stayed on screen"],
        @"instagram_organic_sub_impression": @[@"多圖串文裡的單張圖片出現在畫面上", @"Single photo in a multi-photo post shown"],
        @"instagram_organic_like":          @[@"按讚（一般串文）", @"Liked a regular post"],
        @"instagram_organic_unlike":        @[@"收回讚（一般串文）", @"Unliked a regular post"],
        @"instagram_organic_brand_profile": @[@"瀏覽品牌或創作者帳號", @"Viewed a brand or creator account"],
        @"ig_profile_action":               @[@"個人檔案頁的操作（進入、追蹤、點擊等）", @"Profile page actions (open, follow, taps)"],
        @"threads_profile_tag_impression":  @[@"個人檔案上的標籤出現在畫面上", @"Profile tag shown"],
        @"threads_profile_tag_unit_impression": @[@"個人檔案的標籤區塊出現在畫面上", @"Profile tag section shown"],
        @"threads_monthly_views_impression": @[@"個人檔案的每月瀏覽次數出現在畫面上", @"Monthly views on a profile shown"],
        @"threads_message_cta_impression":  @[@"「傳送訊息」按鈕出現在畫面上", @"Message button shown"],
        @"threads_spoiler_reveal_tap":      @[@"點開被遮住的防雷內容", @"Revealed spoiler content"],
        @"barcelona_growth_integration_impression": @[@"推廣區塊出現在畫面上（例如邀請好友、跨 App 推廣）", @"Growth promotion shown (e.g. invite friends, cross-app)"],
        @"instagram_session_throughput":    @[@"本次使用期間的資料傳輸量", @"Data transferred this session"],
        @"igfeeditemtracker_igusersession_leak_analysis_event_reported": @[@"記憶體洩漏檢測回報（開發除錯用）", @"Memory leak check (debugging)"],
        @"threads_feed_menu_button_impression": @[@"動態串文的「⋯」選單按鈕出現在畫面上", @"Post \"…\" menu button shown in feed"],
    }; });
    return d;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *TPAnaWords(void) {
    static NSDictionary *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = @{
        @"feed": @[@"動態", @"feed"], @"timeline": @[@"動態", @"feed"], @"home": @[@"首頁", @"home"],
        @"item": @[@"項目", @"item"], @"post": @[@"串文", @"post"], @"posts": @[@"串文", @"posts"],
        @"thread": @[@"串文", @"thread"], @"text": @[@"文字", @"text"], @"reply": @[@"回覆", @"reply"],
        @"replies": @[@"回覆", @"replies"], @"comment": @[@"留言", @"comment"], @"repost": @[@"轉發", @"repost"],
        @"quote": @[@"引用", @"quote"], @"profile": @[@"個人檔案", @"profile"], @"user": @[@"使用者", @"user"],
        @"account": @[@"帳號", @"account"], @"search": @[@"搜尋", @"search"], @"activity": @[@"動態通知頁", @"activity"],
        @"notification": @[@"通知", @"notification"], @"notifications": @[@"通知", @"notifications"],
        @"push": @[@"推播", @"push"], @"inbox": @[@"收件匣", @"inbox"], @"direct": @[@"私訊", @"DM"],
        @"dm": @[@"私訊", @"DM"], @"message": @[@"訊息", @"message"], @"messaging": @[@"訊息", @"messaging"],
        @"slide": @[@"私訊", @"DM"], @"media": @[@"媒體", @"media"], @"image": @[@"圖片", @"image"],
        @"photo": @[@"相片", @"photo"], @"video": @[@"影片", @"video"], @"carousel": @[@"多圖", @"carousel"],
        @"link": @[@"連結", @"link"], @"url": @[@"網址", @"URL"], @"tab": @[@"分頁", @"tab"],
        @"composer": @[@"發文畫面", @"composer"], @"compose": @[@"發文", @"compose"], @"camera": @[@"相機", @"camera"],
        @"keyboard": @[@"鍵盤", @"keyboard"], @"sheet": @[@"選單", @"sheet"], @"menu": @[@"選單", @"menu"],
        @"button": @[@"按鈕", @"button"], @"dialog": @[@"對話框", @"dialog"], @"nux": @[@"新手提示", @"onboarding tip"],
        @"suggested": @[@"推薦", @"suggested"], @"recommendation": @[@"推薦", @"recommendation"], @"recs": @[@"推薦", @"recs"],
        @"aymf": @[@"為你推薦", @"suggested for you"], @"community": @[@"社群", @"community"], @"topic": @[@"主題", @"topic"],
        @"tag": @[@"標籤", @"tag"], @"hashtag": @[@"主題標籤", @"hashtag"], @"ad": @[@"廣告", @"ad"], @"ads": @[@"廣告", @"ads"],
        @"sponsored": @[@"贊助內容", @"sponsored"], @"story": @[@"限時動態", @"story"], @"reel": @[@"短片", @"reel"],
        @"session": @[@"使用期間", @"session"], @"app": @[@"App", @"app"], @"page": @[@"頁面", @"page"],
        @"screen": @[@"畫面", @"screen"], @"view": @[@"畫面", @"view"], @"settings": @[@"設定", @"settings"],
        @"impression": @[@"曝光（出現在畫面上）", @"impression"], @"impressions": @[@"曝光", @"impressions"],
        @"vpv": @[@"停留時間", @"view time"], @"viewport": @[@"可見範圍", @"viewport"], @"visible": @[@"可見", @"visible"],
        @"tap": @[@"點擊", @"tap"], @"tapped": @[@"點擊", @"tapped"], @"click": @[@"點擊", @"click"], @"clicked": @[@"點擊", @"clicked"],
        @"press": @[@"按下", @"press"], @"long": @[@"長", @"long"], @"swipe": @[@"滑動", @"swipe"], @"scroll": @[@"捲動", @"scroll"],
        @"open": @[@"開啟", @"open"], @"opened": @[@"開啟", @"opened"], @"close": @[@"關閉", @"close"], @"closed": @[@"關閉", @"closed"],
        @"dismiss": @[@"關閉", @"dismiss"], @"show": @[@"顯示", @"show"], @"shown": @[@"顯示", @"shown"], @"hide": @[@"隱藏", @"hide"],
        @"display": @[@"顯示", @"display"], @"displayed": @[@"顯示", @"displayed"], @"render": @[@"繪製", @"render"],
        @"like": @[@"按讚", @"like"], @"unlike": @[@"收回讚", @"unlike"], @"share": @[@"分享", @"share"], @"copy": @[@"複製", @"copy"],
        @"follow": @[@"追蹤", @"follow"], @"unfollow": @[@"取消追蹤", @"unfollow"], @"mute": @[@"靜音", @"mute"], @"block": @[@"封鎖", @"block"],
        @"save": @[@"儲存", @"save"], @"send": @[@"送出", @"send"], @"sent": @[@"已送出", @"sent"], @"receive": @[@"收到", @"receive"],
        @"received": @[@"收到", @"received"], @"read": @[@"已讀", @"read"], @"seen": @[@"看過", @"seen"], @"typing": @[@"輸入中", @"typing"],
        @"play": @[@"播放", @"play"], @"playing": @[@"播放", @"playing"], @"pause": @[@"暫停", @"pause"], @"paused": @[@"暫停", @"paused"],
        @"start": @[@"開始", @"start"], @"started": @[@"開始", @"started"], @"end": @[@"結束", @"end"], @"ended": @[@"結束", @"ended"],
        @"exit": @[@"離開", @"exit"], @"exited": @[@"離開", @"exited"], @"enter": @[@"進入", @"enter"], @"navigation": @[@"切換頁面", @"navigation"],
        @"load": @[@"載入", @"load"], @"loaded": @[@"載入完成", @"loaded"], @"loading": @[@"載入中", @"loading"], @"fetch": @[@"讀取", @"fetch"],
        @"refresh": @[@"重新整理", @"refresh"], @"prefetch": @[@"預先載入", @"prefetch"], @"download": @[@"下載", @"download"],
        @"upload": @[@"上傳", @"upload"], @"request": @[@"請求", @"request"], @"response": @[@"回應", @"response"],
        @"success": @[@"成功", @"success"], @"succeeded": @[@"成功", @"succeeded"], @"fail": @[@"失敗", @"fail"],
        @"failed": @[@"失敗", @"failed"], @"failure": @[@"失敗", @"failure"], @"error": @[@"錯誤", @"error"], @"cancel": @[@"取消", @"cancel"],
        @"login": @[@"登入", @"login"], @"logout": @[@"登出", @"logout"], @"switch": @[@"切換", @"switch"], @"edit": @[@"編輯", @"edit"],
        @"delete": @[@"刪除", @"delete"], @"report": @[@"檢舉", @"report"], @"translate": @[@"翻譯", @"translate"],
        @"time": @[@"時間", @"time"], @"spent": @[@"花費", @"spent"], @"duration": @[@"時長", @"duration"], @"perf": @[@"效能", @"performance"],
        @"performance": @[@"效能", @"performance"], @"latency": @[@"延遲", @"latency"], @"frame": @[@"畫面格", @"frame"],
        @"frames": @[@"畫面格", @"frames"], @"drop": @[@"掉格", @"drop"], @"dropped": @[@"掉格", @"dropped"], @"memory": @[@"記憶體", @"memory"],
        @"network": @[@"網路", @"network"], @"cache": @[@"快取", @"cache"], @"cold": @[@"冷", @"cold"], @"warm": @[@"熱", @"warm"],
        @"startup": @[@"啟動", @"startup"], @"launch": @[@"啟動", @"launch"], @"foreground": @[@"回到前景", @"foreground"],
        @"background": @[@"進入背景", @"background"], @"state": @[@"狀態", @"state"], @"battery": @[@"電池", @"battery"],
        @"device": @[@"裝置", @"device"], @"bandwidth": @[@"頻寬", @"bandwidth"], @"connection": @[@"連線", @"connection"],
        @"qe": @[@"實驗", @"experiment"], @"exposure": @[@"分組紀錄", @"exposure"], @"experiment": @[@"實驗", @"experiment"],
        @"gk": @[@"功能開關", @"feature gate"], @"config": @[@"設定值", @"config"], @"sync": @[@"同步", @"sync"],
        @"count": @[@"次數", @"count"], @"stats": @[@"統計", @"stats"], @"event": @[@"事件", @"event"], @"events": @[@"事件", @"events"],
        @"bit": @[@"逐秒", @"bit"], @"array": @[@"記錄", @"array"], @"client": @[@"用戶端", @"client"], @"server": @[@"伺服器", @"server"],
        @"bloks": @[@"介面元件", @"UI component"], @"mobile": @[@"行動裝置", @"mobile"], @"log": @[@"紀錄", @"log"],
        @"param": @[@"參數", @"parameter"], @"access": @[@"讀取", @"access"], @"without": @[@"未", @"without"],
        @"trigger": @[@"觸發", @"trigger"], @"flow": @[@"流程", @"flow"], @"privacy": @[@"隱私", @"privacy"],
        @"installations": @[@"安裝", @"installations"], @"install": @[@"安裝", @"install"], @"badging": @[@"紅點標記", @"badge"],
        @"badge": @[@"紅點標記", @"badge"], @"setting": @[@"設定", @"setting"], @"delivery": @[@"投放", @"delivery"],
        @"action": @[@"操作", @"action"],
        @"organic": @[@"一般內容", @"organic"], @"vpvd": @[@"停留時間", @"view time"], @"imp": @[@"曝光", @"impression"],
        @"registration": @[@"登記", @"registration"], @"initiated": @[@"開始", @"initiated"], @"upsells": @[@"推廣", @"promotion"],
        @"upsell": @[@"推廣", @"promotion"], @"product": @[@"產品", @"product"], @"header": @[@"上方標籤", @"header"],
        @"context": @[@"情境", @"context"], @"trend": @[@"熱門話題", @"trend"], @"trends": @[@"熱門話題", @"trends"], @"component": @[@"元件", @"component"], @"graphql": @[@"資料請求", @"data request"],
    }; });
    return d;
}

static NSString *TPAnaDescribe(NSString *name, BOOL zh) {
    NSUInteger li = zh ? 0 : 1;
    NSString *low = name.lowercaseString;
    NSArray *known = TPAnaKnownEvents()[low];
    if (known) return known[li];
    NSArray *parts = [low componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_:.-/ "]];
    NSMutableArray *out = [NSMutableArray new];
    NSUInteger hit = 0, total = 0;
    for (NSString *w in parts) {
        if (!w.length) continue;
        if ([@[@"ig", @"instagram", @"barcelona", @"bcn", @"xth", @"fb", @"meta", @"textapp", @"ios", @"threads"] containsObject:w]) continue;
        total++;
        NSArray *t = TPAnaWords()[w];
        if (t) { hit++; if (![out.lastObject isEqualToString:t[li]]) [out addObject:t[li]]; }
    }
    if (!hit || hit * 2 < total) return nil;
    return [out componentsJoinedByString:zh ? @"・" : @" · "];
}

NSString *TPAnalyticsLogReport(void) {
    NSDictionary *counts; NSArray *recent; NSUInteger total;
    @synchronized ([TPPrefs class]) { counts = [gTPAnaCounts copy]; recent = [gTPAnaLast.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"t"] compare:a[@"t"]]; }]; total = gTPAnaTotal; }
    if (!total) return nil;
    BOOL zh = ![TPL(@"Top Events") isEqualToString:@"Top Events"];
    BOOL blocking = [TPPrefs boolForKey:TPKeyBlockAnalytics];
    NSMutableString *r = [NSMutableString stringWithFormat:@"ThreadsPulse %@\n\n", TP_VERSION];
    [r appendFormat:@"%@\n", blocking ? TPL(@"Block Analytics: On") : TPL(@"Block Analytics: Off")];
    [r appendFormat:@"%@\n", blocking ? TPL(@"Nothing below was sent") : TPL(@"Everything below was sent")];
    [r appendFormat:TPL(@"%lu events while using the app (%lu types)"), (unsigned long)total, (unsigned long)counts.count];
    [r appendFormat:@"\n\n【%@】\n", TPL(@"Top Events")];
    NSArray *names = [counts keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
    NSUInteger i = 0;
    for (NSString *n in names) {
        if (i++ >= 60) { [r appendFormat:TPL(@"…and %lu more types"), (unsigned long)(names.count - 60)]; [r appendString:@"\n"]; break; }
        NSString *desc = TPAnaDescribe(n, zh) ?: TPL(@"Unknown");
        [r appendFormat:@"\n%@\n%@ · %@\n", desc, [NSString stringWithFormat:TPL(@"%@ times"), counts[n]], n];
    }
    [r appendFormat:@"\n【%@】\n%@\n", TPL(@"Recent Events"), TPL(@"Latest one of each type")];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss";
    for (NSDictionary *it in [recent subarrayWithRange:NSMakeRange(0, MIN(recent.count, kTPAnaRecentMax))]) {
        NSString *desc = TPAnaDescribe(it[@"n"], zh);
        [r appendFormat:@"\n%@ %@\n%@%@\n", [f stringFromDate:it[@"t"]], desc ?: it[@"n"],
                        desc ? [it[@"n"] stringByAppendingString:@"\n"] : @"", TPAnaPayloadString(it[@"e"])];
    }
    [r appendFormat:@"\n%@", TPL(@"Contains your user ID and post IDs. Check before sharing.")];
    return r;
}

%group BlockAnalytics

%hook FBAnalyticsCoreLogger
- (void)_captureAnalyticsEvent:(id)event {
    BOOL block = [TPPrefs boolForKey:TPKeyBlockAnalytics];
    TPRecordAnalytics(event, block);
    if (block) { __sync_fetch_and_add(&gTPAnalyticsDropped, 1); return; }
    %orig;
}
- (BOOL)_captureAnalyticsEventForBatchUpload:(id)event {
    if ([TPPrefs boolForKey:TPKeyBlockAnalytics]) return YES;
    return %orig;
}
- (BOOL)_shouldStreamEvent:(id)event {
    if ([TPPrefs boolForKey:TPKeyBlockAnalytics]) return NO;
    return %orig;
}
%end

%end

typedef BOOL (*TPPerformIMP)(id, SEL, id, void *);
static TPPerformIMP orig_TPAnalyticsPerform, noop_TPAnalyticsPerform;
static BOOL tp_AnalyticsPerform(id self, SEL _cmd, id context, void *requestContext) {
    if (noop_TPAnalyticsPerform && [TPPrefs boolForKey:TPKeyBlockAnalytics])
        return noop_TPAnalyticsPerform(self, _cmd, context, requestContext);
    return orig_TPAnalyticsPerform(self, _cmd, context, requestContext);
}

// The upload method takes a large struct, passed by pointer on arm64, so the replacement is
// only installed when both implementations have identical type encodings.
static void TPInstallAnalyticsUploadBlock(void) {
    SEL sel = NSSelectorFromString(@"performRequestWithContext:requestContext:");
    Class noop = objc_getClass("FBAnalyticsNoOpNetworkConfigurator");
    Class real = objc_getClass("IGAnalyticsNetworkConfigurator");
    Method nm = noop ? class_getInstanceMethod(noop, sel) : NULL;
    Method rm = real ? class_getInstanceMethod(real, sel) : NULL;
    if (!nm || !rm || method_getImplementation(nm) == method_getImplementation(rm)) return;
    if (strcmp(method_getTypeEncoding(nm), method_getTypeEncoding(rm)) != 0) return;
    noop_TPAnalyticsPerform = (TPPerformIMP)method_getImplementation(nm);
    orig_TPAnalyticsPerform = (TPPerformIMP)method_setImplementation(rm, (IMP)tp_AnalyticsPerform);
}

// Links in posts and bios go through BCNLinkHandlerImpl (an ObjC protocol, so calls use ObjC
// dispatch). threads.com / threads.net and non-web links keep the default behavior.
static NSURL *TPExternalBrowserURL(id url) {
    if (![TPPrefs boolForKey:TPKeyExternalBrowser] || ![url isKindOfClass:[NSURL class]]) return nil;
    NSURL *target = url;
    NSURLComponents *c = [NSURLComponents componentsWithURL:target resolvingAgainstBaseURL:NO];
    if (c && [TPURLCleaner isRedirectHost:c.host]) {
        for (NSURLQueryItem *q in c.queryItems)
            if ([q.name isEqualToString:@"u"] && q.value.length) { NSURL *inner = [NSURL URLWithString:q.value]; if (inner) target = inner; break; }
    }
    NSString *scheme = target.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;
    NSString *host = target.host.lowercaseString ?: @"";
    for (NSString *own in @[@"threads.net", @"threads.com"])
        if ([host isEqualToString:own] || [host hasSuffix:[@"." stringByAppendingString:own]]) return nil;
    return [TPURLCleaner cleanURL:target];
}

static BOOL TPOpenExternally(id url) {
    NSURL *target = TPExternalBrowserURL(url);
    if (!target) return NO;
    [[UIApplication sharedApplication] openURL:target options:@{} completionHandler:nil];
    return YES;
}

%group ExternalBrowser

%hook _TtC20BCNLinkHandlerPlugin18BCNLinkHandlerImpl
- (void)handleLinkWithURL:(id)url containerModule:(id)module presenter:(id)presenter {
    if (TPOpenExternally(url)) return;
    %orig;
}
- (void)handleLinkWithURL:(id)url rawURL:(id)rawURL linkProtectionMetadata:(id)metadata mediaPk:(id)pk mediaAuthorPk:(id)authorPk linkTapLocation:(long long)location containerModule:(id)module sponsoredPostInfo:(id)info rankingInfoToken:(id)token presenter:(id)presenter contextualLoggingParameters:(id)parameters clickSource:(unsigned long long)source animationViewProvider:(id)provider {
    if (TPOpenExternally(url)) return;
    %orig;
}
%end

%end

// Profile header buttons are lazy properties of BCNProfileViewController:
// $__lazy_storage_$_searchButton and $__lazy_storage_$_appSwitcherButton (Instagram).
// Outside a stack view the remaining buttons are shifted with a transform. When both are
// hidden, a button that would be shifted twice takes the larger shift, not the sum.
static const void *kTPHiddenProfileViewsKey = &kTPHiddenProfileViewsKey;

static UIView *TPIGButtonSlot(UIView *button) {
    UIView *v = button;
    while (v.superview && ![v.superview isKindOfClass:[UIStackView class]] && v.superview.subviews.count == 1) v = v.superview;
    return v;
}

static const void *kTPShiftedViewsKey = &kTPShiftedViewsKey;

static void TPResetShifted(UIViewController *vc) {
    for (TPWeakBox *box in (NSArray *)objc_getAssociatedObject(vc, kTPShiftedViewsKey)) {
        UIView *v = box.object;
        if (v) v.transform = CGAffineTransformIdentity;
    }
    objc_setAssociatedObject(vc, kTPShiftedViewsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *TPProfileButton(UIViewController *vc, const char *ivar) {
    Ivar iv = class_getInstanceVariable(object_getClass(vc), ivar);
    UIView *b = iv ? object_getIvar(vc, iv) : nil;
    return [b isKindOfClass:[UIView class]] && b.superview ? b : nil;
}

static void TPApplyHideIGButton(UIViewController *vc) {
    for (TPWeakBox *box in (NSArray *)objc_getAssociatedObject(vc, kTPHiddenProfileViewsKey)) ((UIView *)box.object).hidden = NO;
    objc_setAssociatedObject(vc, kTPHiddenProfileViewsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TPResetShifted(vc);

    NSMutableArray<UIView *> *slots = [NSMutableArray array];
    if ([TPPrefs boolForKey:TPKeyHideIGButton]) { UIView *b = TPProfileButton(vc, "$__lazy_storage_$_appSwitcherButton"); if (b) [slots addObject:TPIGButtonSlot(b)]; }
    if ([TPPrefs boolForKey:TPKeyHideProfileSearch]) { UIView *b = TPProfileButton(vc, "$__lazy_storage_$_searchButton"); if (b) [slots addObject:TPIGButtonSlot(b)]; }
    if (!slots.count) return;

    NSMutableArray *hiddenBoxes = [NSMutableArray array];
    for (UIView *slot in slots) {
        slot.hidden = YES;
        TPWeakBox *box = [TPWeakBox new]; box.object = slot; [hiddenBoxes addObject:box];
    }
    objc_setAssociatedObject(vc, kTPHiddenProfileViewsKey, hiddenBoxes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMapTable<UIView *, NSNumber *> *shift = [NSMapTable weakToStrongObjectsMapTable];
    for (UIView *slot in slots) {
        if (!slot.superview || [slot.superview isKindOfClass:[UIStackView class]]) continue;
        CGRect f = slot.frame;
        NSMutableArray<UIView *> *left = [NSMutableArray array], *right = [NSMutableArray array];
        CGFloat leftEdge = -CGFLOAT_MAX, rightEdge = CGFLOAT_MAX;
        for (UIView *v in slot.superview.subviews) {
            if ([slots containsObject:v] || v.hidden || v.alpha < 0.01) continue;
            CGRect g = v.frame;
            if (g.size.width > 100 || g.size.height > 100) continue;
            if (CGRectGetMaxY(g) <= CGRectGetMinY(f) || CGRectGetMinY(g) >= CGRectGetMaxY(f)) continue;
            if (CGRectGetMaxX(g) <= CGRectGetMinX(f) + 1) { [left addObject:v]; leftEdge = MAX(leftEdge, CGRectGetMaxX(g)); }
            else if (CGRectGetMinX(g) >= CGRectGetMaxX(f) - 1) { [right addObject:v]; rightEdge = MIN(rightEdge, CGRectGetMinX(g)); }
        }
        NSArray *movers; CGFloat dx;
        if (left.count) { movers = left; dx = CGRectGetMaxX(f) - leftEdge; }
        else if (right.count) { movers = right; dx = CGRectGetMinX(f) - rightEdge; }
        else continue;
        for (UIView *v in movers) {
            double prev = [[shift objectForKey:v] doubleValue];
            if (fabs(dx) > fabs(prev)) [shift setObject:@(dx) forKey:v];
        }
    }
    NSMutableArray *boxes = [NSMutableArray array];
    for (UIView *v in shift) {
        v.transform = CGAffineTransformMakeTranslation([[shift objectForKey:v] doubleValue], 0);
        TPWeakBox *b = [TPWeakBox new]; b.object = v; [boxes addObject:b];
    }
    objc_setAssociatedObject(vc, kTPShiftedViewsKey, boxes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group HideIGButton

%hook _TtC10BCNProfile24BCNProfileViewController
- (void)viewDidLayoutSubviews {
    %orig;
    TPApplyHideIGButton((UIViewController *)self);
}
%end

%end

// Long-press on the Home tab. Every tab long-press (e.g. switching accounts on the profile tab)
// goes through handleTabBarLongPress:; only presses that begin on the first tab are taken.
static void TPCollectTabButtons(UIView *v, NSMutableArray<UIView *> *out, int depth) {
    if (depth > 8) return;
    for (UIView *s in v.subviews) {
        NSString *cls = NSStringFromClass([s class]);
        if (!s.hidden && s.alpha > 0.01 && ([cls containsString:@"TabButton"] || [cls containsString:@"TabBarButton"])) [out addObject:s];
        else TPCollectTabButtons(s, out, depth + 1);
    }
}

static BOOL TPIsHomeTabPress(UIGestureRecognizer *g) {
    UIView *bar = g.view;
    if (!bar) return NO;
    CGPoint p = [g locationInView:bar];
    BOOL rtl = bar.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    TPCollectTabButtons(bar, buttons, 0);
    if (buttons.count >= 2) {
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            CGFloat ax = [a convertPoint:CGPointZero toView:bar].x, bx = [b convertPoint:CGPointZero toView:bar].x;
            return ax < bx ? NSOrderedAscending : ax > bx ? NSOrderedDescending : NSOrderedSame;
        }];
        UIView *home = rtl ? buttons.lastObject : buttons.firstObject;
        CGRect f = [home convertRect:home.bounds toView:bar];
        return p.x >= CGRectGetMinX(f) && p.x <= CGRectGetMaxX(f);
    }
    NSUInteger n = [bar isKindOfClass:[UITabBar class]] && ((UITabBar *)bar).items.count ? ((UITabBar *)bar).items.count : 5;
    CGFloat cell = bar.bounds.size.width / n;
    return rtl ? p.x >= bar.bounds.size.width - cell : p.x <= cell;
}

static const void *kTPHomePressKey = &kTPHomePressKey;

%group HomeLongPress

%hook _TtC26BCNLucentTabBarCoordinator26BCNLucentTabBarCoordinator
- (void)handleTabBarLongPress:(UIGestureRecognizer *)press {
    BOOL began = [press isKindOfClass:[UIGestureRecognizer class]] && press.state == UIGestureRecognizerStateBegan;
    if (![TPPrefs boolForKey:TPKeyHomeLongPress] || ![press isKindOfClass:[UIGestureRecognizer class]]) {
        if (began) TPDebug([NSString stringWithFormat:@"%@: %@", TPL(@"Long-press tab"), TPL(@"feature is off")]);
        %orig; return;
    }
    if (began) {
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        TPCollectTabButtons(press.view, buttons, 0);
        BOOL home = TPIsHomeTabPress(press);
        TPDebug([NSString stringWithFormat:@"%@: %@ (%@ %lu · x %.0f / %.0f)", TPL(@"Long-press tab"),
                 TPL(home ? @"Home tab" : @"not the Home tab"), NSStringFromClass([press.view class]),
                 (unsigned long)buttons.count, [press locationInView:press.view].x, press.view.bounds.size.width]);
        objc_setAssociatedObject(press, kTPHomePressKey, home ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!home) { %orig; return; }
        gTPSuppressTabSelectUntil = CFAbsoluteTimeGetCurrent() + 10;
        [TPUI hapticLight];
        [TPSettingsViewController present];
        return;
    }
    BOOL mine = objc_getAssociatedObject(press, kTPHomePressKey) != nil;
    if (press.state == UIGestureRecognizerStateEnded || press.state == UIGestureRecognizerStateCancelled
        || press.state == UIGestureRecognizerStateFailed) {
        objc_setAssociatedObject(press, kTPHomePressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (mine) gTPSuppressTabSelectUntil = CFAbsoluteTimeGetCurrent() + 0.6;
    }
    if (!mine) %orig;
}
%end

%end

// Hide Seen Status.
// Threads marks a chat as read with BCNSlideMDCoreMarkThreadReadMutationBuilder, carrying the
// timestamp read up to. When blocked, that timestamp is replaced with the position this chat
// has already shown to the other person (the watermark), or 0. Sending 0 after a Seen was
// shown would move the server's read position backwards and make that Seen disappear.
// Chat ids arrive as NSString, NSNumber or wrapped values, so they are normalized here.
static NSString *TPThreadKey(id fbid) {
    if (!fbid) return nil;
    if ([fbid isKindOfClass:[NSString class]]) return fbid;
    if ([fbid isKindOfClass:[NSNumber class]]) return [fbid stringValue];
    id raw = [TPDownloader safeValue:fbid key:@"rawValue"];
    if ([raw isKindOfClass:[NSString class]]) return raw;
    if ([raw isKindOfClass:[NSNumber class]]) return [raw stringValue];
    NSString *best = nil;
    for (NSString *part in [[fbid description] componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]])
        if (part.length > best.length) best = part;
    return best.length >= 6 ? best : [fbid description];
}

static NSString *gTPOpenChatKey;
static BOOL gTPOpenChatShowsSeen;

static void TPSendSeenNow(NSString *k);
static BOOL TPChatShowsSeen(NSString *key);

static void TPAllowSeenAfterReply(id fbid) {
    NSString *k = TPThreadKey(fbid);
    if (!k.length) return;
    if (TPChatShowsSeen(k)) return;
    if (![TPPrefs boolForKey:TPKeySeenOnReply]) return;
    static NSMutableDictionary<NSString *, NSNumber *> *lastReply;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized ([TPPrefs class]) {
        if (!lastReply) lastReply = [NSMutableDictionary dictionary];
        if (now - [lastReply[k] doubleValue] < 1.5) return;
        lastReply[k] = @(now);
    }
    if ([NSThread isMainThread]) TPSendSeenNow(k);
    else dispatch_async(dispatch_get_main_queue(), ^{ TPSendSeenNow(k); });
}

static NSString *const kTPSeenChatsKey = @"tp_seen_allowed_chats";

static BOOL TPChatShowsSeen(NSString *key) {
    if (!key.length) return NO;
    NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:kTPSeenChatsKey];
    return [list containsObject:key];
}

static void TPSetChatShowsSeen(NSString *key, BOOL show) {
    if (!key.length) return;
    NSMutableArray *list = [[[NSUserDefaults standardUserDefaults] arrayForKey:kTPSeenChatsKey] mutableCopy] ?: [NSMutableArray array];
    [list removeObject:key];
    if (show) [list addObject:key];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kTPSeenChatsKey];
}

// Sending Seen on reply (or when the eye is turned on) rebuilds the read request from the last
// blocked arguments and sends it through the same GraphQL service and method Threads used,
// which are recorded from Threads' own read requests below.
static const void *kTPMarkReadTag = &kTPMarkReadTag;
static NSMutableDictionary<NSString *, NSDictionary *> *gTPLastReadArgs;
static __weak id gTPGQLService;
static int gTPMarkReadVia;
static BOOL gTPForceSeen;

static id TPTagMarkRead(id b) {
    if (b) objc_setAssociatedObject(b, kTPMarkReadTag, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return b;
}

static NSMutableDictionary<NSString *, NSNumber *> *gTPSeenSentAt;
static NSMutableDictionary<NSString *, NSNumber *> *gTPSeenWatermark;

// Messages held until the server accepts the Seen (released on response, at most 0.8 s).
static NSMutableDictionary<NSString *, NSMutableArray *> *gTPHeldMessages;

static void TPReleaseHeldMessages(NSString *k) {
    NSArray *blocks;
    @synchronized ([TPPrefs class]) { blocks = gTPHeldMessages[k]; [gTPHeldMessages removeObjectForKey:k]; }
    for (dispatch_block_t b in blocks) b();
}

static void TPRecordWatermark(NSString *k, id ms) {
    long long v = [ms respondsToSelector:@selector(longLongValue)] ? [ms longLongValue] : 0;
    if (!k.length || v <= 0) return;
    @synchronized ([TPPrefs class]) {
        if (!gTPSeenWatermark) gTPSeenWatermark = [NSMutableDictionary dictionary];
        if (v > [gTPSeenWatermark[k] longLongValue]) gTPSeenWatermark[k] = @(v);
    }
}

static void TPSendSeenNow(NSString *k) {
    NSDictionary *args;
    @synchronized ([TPPrefs class]) { args = gTPLastReadArgs[k]; }
    id service = gTPGQLService;
    if (!args) { TPDebugNow(@"Seen: no read to resend for this chat yet"); return; }
    if (!service || !gTPMarkReadVia) { TPDebugNow(@"Seen: GraphQL service not found"); return; }
    long long nowMs = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    long long otidVal = (nowMs << 22) | arc4random_uniform(1 << 22);
    BOOL otidStr = [args[@"otidStr"] boolValue], msStr = [args[@"msStr"] boolValue];
    id otid = otidStr ? [NSString stringWithFormat:@"%lld", otidVal] : @(otidVal);
    id ms = args[@"ms"] ?: (msStr ? [NSString stringWithFormat:@"%lld", nowMs] : @(nowMs));
    Class cls = objc_getClass("BCNSlideMDCoreMarkThreadReadMutationBuilder");
    gTPForceSeen = YES;
    id b = ((id (*)(id, SEL, id, id, id))objc_msgSend)(cls, @selector(builderWithOfflineThreadingId:threadFbid:timestampMs:), otid, args[@"fbid"], ms);
    gTPForceSeen = NO;
    if (!b) { TPDebugNow(@"Seen: builder failed"); return; }
    TPRecordWatermark(k, ms);
    @synchronized ([TPPrefs class]) {
        if (!gTPSeenSentAt) gTPSeenSentAt = [NSMutableDictionary dictionary];
        gTPSeenSentAt[k] = @(CFAbsoluteTimeGetCurrent());
    }
    void (^update)(id) = ^(id x) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ TPReleaseHeldMessages(k); });
    };
    void (^failure)(id) = ^(id e) {
        TPDebugNow([NSString stringWithFormat:@"Seen: send failed %@", e]);
        TPReleaseHeldMessages(k);
    };
    dispatch_queue_t q = dispatch_get_main_queue();
    @try {
        switch (gTPMarkReadVia) {
            case 1: ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(b, @selector(handleWithService:updateCallback:failureCallback:callbackQueue:), service, update, failure, q); break;
            case 2: ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(b, @selector(handleFiniteWithService:updateCallback:failureCallback:callbackQueue:), service, update, failure, q); break;
            case 3: ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(service, @selector(initiateRequest:initialData:updateCallback:failureCallback:callbackQueue:), [b request], nil, update, failure, q); break;
            case 4: ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(service, @selector(initiateFiniteRequest:initialData:updateCallback:failureCallback:callbackQueue:), [b request], nil, update, failure, q); break;
        }
        TPDebugNow(TPL(@"Seen sent"));
    } @catch (NSException *e) {
        TPDebugNow([NSString stringWithFormat:@"Seen: %@", e.reason]);
        TPReleaseHeldMessages(k);
    }
}

%group NoSeen
%hook BCNSlideMDCoreMarkThreadReadMutationBuilder
+ (id)builderWithOfflineThreadingId:(id)otid threadFbid:(id)fbid timestampMs:(id)ms {
    if (gTPForceSeen) return TPTagMarkRead(%orig);
    if (![TPPrefs boolForKey:TPKeyNoSeen]) return TPTagMarkRead(%orig);
    NSString *argKey = TPThreadKey(fbid);
    if (argKey.length && fbid) @synchronized ([TPPrefs class]) {
        if (!gTPLastReadArgs) gTPLastReadArgs = [NSMutableDictionary dictionary];
        NSMutableDictionary *d = [@{ @"fbid": fbid, @"otidStr": @([otid isKindOfClass:[NSString class]]),
                                     @"msStr": @([ms isKindOfClass:[NSString class]]) } mutableCopy];
        if (ms && [ms longLongValue] > 0) d[@"ms"] = ms;
        gTPLastReadArgs[argKey] = d;
    }
    if (TPChatShowsSeen(TPThreadKey(fbid))) { TPRecordWatermark(argKey, ms); return TPTagMarkRead(%orig); }
    if (gTPOpenChatShowsSeen && gTPOpenChatKey.length) {
        NSString *k = TPThreadKey(fbid), *otidKey = TPThreadKey(otid);
        if (!k.length || [k isEqualToString:gTPOpenChatKey] || [gTPOpenChatKey containsString:k] || [k containsString:gTPOpenChatKey]
            || [otidKey isEqualToString:gTPOpenChatKey]) { TPRecordWatermark(argKey, ms); return TPTagMarkRead(%orig); }
        TPDebug([NSString stringWithFormat:@"Seen: %@ ≠ %@", k, gTPOpenChatKey]);
    }
    long long wm;
    @synchronized ([TPPrefs class]) { wm = [gTPSeenWatermark[argKey] longLongValue]; }
    id zero = [ms isKindOfClass:[NSString class]] ? [NSString stringWithFormat:@"%lld", wm] : @(wm);
    static NSMutableDictionary<NSString *, NSNumber *> *lastToast;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lastToast = [NSMutableDictionary dictionary]; });
    NSString *k = TPThreadKey(fbid) ?: @"";
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized ([TPPrefs class]) {
        if (now - [lastToast[k] doubleValue] > 60) { lastToast[k] = @(now); TPDebug(TPL(@"Seen status blocked")); }
    }
    return TPTagMarkRead(%orig(otid, fbid, zero));
}
%end

%hook PNGraphQLQueryBuilder
- (id)handleWithService:(id)service updateCallback:(id)u failureCallback:(id)f callbackQueue:(id)q {
    if (objc_getAssociatedObject(self, kTPMarkReadTag)) { gTPGQLService = service; gTPMarkReadVia = 1; }
    return %orig;
}
- (id)handleFiniteWithService:(id)service updateCallback:(id)u failureCallback:(id)f callbackQueue:(id)q {
    if (objc_getAssociatedObject(self, kTPMarkReadTag)) { gTPGQLService = service; gTPMarkReadVia = 2; }
    return %orig;
}
- (id)request {
    id r = %orig;
    if (r && objc_getAssociatedObject(self, kTPMarkReadTag)) objc_setAssociatedObject(r, kTPMarkReadTag, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return r;
}
%end

%hook PNPandoGraphQLService
- (id)initiateRequest:(id)req initialData:(id)d updateCallback:(id)u failureCallback:(id)f callbackQueue:(id)q {
    if (req && objc_getAssociatedObject(req, kTPMarkReadTag) && gTPMarkReadVia < 1) { gTPGQLService = self; gTPMarkReadVia = 3; }
    return %orig;
}
- (id)initiateFiniteRequest:(id)req initialData:(id)d updateCallback:(id)u failureCallback:(id)f callbackQueue:(id)q {
    if (req && objc_getAssociatedObject(req, kTPMarkReadTag) && gTPMarkReadVia < 1) { gTPGQLService = self; gTPMarkReadVia = 4; }
    return %orig;
}
%end

// If Seen arrives together with the reply, the reply becomes the last message on the other
// person's screen and Seen has nowhere to show. A message sent right after a Seen is held
// until the server accepts the Seen.
%hook MDCoreSendService
- (void)sendMutationWithAppDataModel:(id)model offlineThreadingId:(id)otid optimisticImages:(id)images syncGroupId:(int)group {
    Ivar iv = model && [TPPrefs boolForKey:TPKeyNoSeen] ? class_getInstanceVariable(object_getClass(model), "_outgoingMessagePayload") : NULL;
    id payload = iv ? object_getIvar(model, iv) : nil;
    NSString *k = payload ? TPThreadKey([TPDownloader safeValue:payload key:@"threadFbid"]) : nil;
    BOOL hold = NO;
    if (k.length) @synchronized ([TPPrefs class]) { hold = CFAbsoluteTimeGetCurrent() - [gTPSeenSentAt[k] doubleValue] < 2; }
    if (!hold) { %orig; return; }
    TPDebug(TPL(@"Seen sent first, message follows"));
    dispatch_block_t send = ^{ %orig(model, otid, images, group); };
    __block BOOL done = NO;
    dispatch_block_t once = ^{ if (done) return; done = YES; send(); };
    @synchronized ([TPPrefs class]) {
        if (!gTPHeldMessages) gTPHeldMessages = [NSMutableDictionary dictionary];
        if (!gTPHeldMessages[k]) gTPHeldMessages[k] = [NSMutableArray array];
        [gTPHeldMessages[k] addObject:[once copy]];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), once);
}
%end

// A reply is detected when Threads builds an outgoing message or a message action. Detecting it
// in MDCoreSendService was wrong: most mutations there are thread updates such as reads.
%hook BCNSlideOutgoingMessagePayload
- (id)initWithOfflineThreadingId:(id)otid threadFbid:(id)fbid senderFbid:(id)sender sendDate:(id)date content:(id)content navChain:(id)chain forwardedMessageId:(id)fwd sendAttribution:(id)attr promptSessionId:(id)ps qnaQuestionId:(id)qid qnaQuestion:(id)q {
    id me = %orig;
    if (me && [TPPrefs boolForKey:TPKeyNoSeen]) {
        TPAllowSeenAfterReply(fbid);
    }
    return me;
}
%end
%hook BCNSlideOutgoingMessageUpdatePayload
- (id)initWithOfflineThreadingId:(id)otid messageId:(id)mid threadFbid:(id)fbid sendDate:(id)date action:(id)action navChain:(id)chain {
    id me = %orig;
    if (me && [TPPrefs boolForKey:TPKeyNoSeen]) {
        TPAllowSeenAfterReply(fbid);
    }
    return me;
}
%end

static const void *kTPSeenButtonKey = &kTPSeenButtonKey;

static void TPSetSeenButtonState(UIButton *b, BOOL showsSeen) {
    [b setImage:[UIImage systemImageNamed:showsSeen ? @"eye" : @"eye.slash"
                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium]]
       forState:UIControlStateNormal];
    b.tintColor = showsSeen ? [TPUI accentIcon] : UIColor.secondaryLabelColor;
    b.accessibilityValue = TPL(showsSeen ? @"This chat shows Seen" : @"This chat hides Seen");
}

static UIViewController *TPChatViewControllerOf(UIView *v) {
    Class chat = objc_getClass("_TtC21BCNSlideMessageListUI33BCNSlideMessageListViewController");
    for (UIResponder *r = v; r; r = r.nextResponder) if (chat && [r isKindOfClass:chat]) return (UIViewController *)r;
    return nil;
}

static NSString *TPChatKeyOf(UIViewController *chat) {
    uint8_t *slot = chat ? TPIvarAddress(chat, "threadId") : NULL;
    uintptr_t p = 0; if (slot) memcpy(&p, slot, 8);
    id thread = p ? (__bridge id)(void *)p : nil;
    return thread ? TPThreadKey(thread) : nil;
}

// Per-chat eye button, placed left of the "..." (moreButton) in
// BCNSlideMessageListNavBarTitleView so it appears and transitions with the title bar.
static UIButton *TPMakeSeenButton(void) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    objc_setAssociatedObject(btn, kTPSeenButtonKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    btn.accessibilityLabel = TPL(@"Seen for This Chat");
    TPSetSeenButtonState(btn, NO);
    __weak UIButton *wb = btn;
    [btn addAction:[UIAction actionWithHandler:^(UIAction *a) {
        UIViewController *chat = TPChatViewControllerOf(wb);
        NSString *key = TPChatKeyOf(chat);
        if (!key.length) { [TPHUD toast:TPL(@"Couldn't find this chat")]; return; }
        BOOL show = !TPChatShowsSeen(key);
        TPSetChatShowsSeen(key, show);
        gTPOpenChatKey = key; gTPOpenChatShowsSeen = show;
        [TPUI hapticLight];
        TPSetSeenButtonState(wb, show);
        [TPHUD toast:TPL(show ? @"This chat shows Seen" : @"This chat hides Seen")];
        if (show) TPSendSeenNow(key);
    }] forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

%hook _TtC21BCNSlideMessageListUI34BCNSlideMessageListNavBarTitleView
- (void)layoutSubviews {
    %orig;
    UIView *me = (UIView *)self;
    UIButton *btn = objc_getAssociatedObject(me, kTPSeenButtonKey);
    if (![TPPrefs boolForKey:TPKeyNoSeen]) { btn.hidden = YES; return; }
    uint8_t *slot = TPIvarAddress(me, "$__lazy_storage_$_moreButton");
    uintptr_t p = 0; if (slot) memcpy(&p, slot, 8);
    UIView *more = p ? (__bridge UIView *)(void *)p : nil;
    if (![more isKindOfClass:[UIView class]] || !more.superview || more.hidden) { btn.hidden = YES; return; }
    if (!btn) {
        btn = TPMakeSeenButton();
        objc_setAssociatedObject(me, kTPSeenButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (btn.superview != more.superview) [more.superview addSubview:btn];
    CGRect m = more.frame;
    btn.frame = CGRectMake(CGRectGetMinX(m) - 8 - 36, CGRectGetMidY(m) - 18, 36, 36);
    NSString *key = TPChatKeyOf(TPChatViewControllerOf(me));
    BOOL shows = TPChatShowsSeen(key);
    if (key.length && me.window) { gTPOpenChatKey = key; gTPOpenChatShowsSeen = shows; }
    TPSetSeenButtonState(btn, shows);
    btn.hidden = NO;
}
- (void)didMoveToWindow {
    %orig;
    if (!((UIView *)self).window) gTPOpenChatShowsSeen = NO;
}
%end
%end

// Hide Typing Status. The activity status is always sent as 0 (stopped typing). Changing the
// thread id instead made the request fail and broke live delivery of new messages.
%group NoTyping
%hook BCNTypingIndicatorPublishEventMutationBuilder
+ (id)builderWithActivityStatus:(id)status threadId:(id)tid {
    if (![TPPrefs boolForKey:TPKeyNoTyping] || ![status isKindOfClass:[NSNumber class]] || [status integerValue] == 0) return %orig;
    static CFAbsoluteTime last;
    if (CFAbsoluteTimeGetCurrent() - last > 60) { last = CFAbsoluteTimeGetCurrent(); TPDebug(TPL(@"Typing status blocked")); }
    return %orig(@0, tid);
}
%end
%end

static const void *kTPApplierNameKey = &kTPApplierNameKey;

// Keep Unsent Messages. An unsend is applied by the Swift BCNSlideDeleteMessageHandler through
// MDCoreDeltaApplyingBridge, which is created with the handler's type name. Delete commands
// produced for that handler are dropped, so the message stays in the local store.
// MDCoreMutationCommand is an enum wrapper; its match method exposes the delete payload.
static id TPDeleteCommandPayload(id cmd) {
    SEL sel = NSSelectorFromString(@"matchUpsertCommand:deleteCommand:updateCommand:deleteAllCommand:deleteFolderCommand:");
    if (![cmd respondsToSelector:sel]) return nil;
    __block id payload = nil;
    __block BOOL del = NO;
    void (^none)(id) = ^(id x) {};
    void (^hit)(id) = ^(id x) { del = YES; payload = x; };
    ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(cmd, sel, none, hit, none, none, none);
    return del ? (payload ?: (id)kCFNull) : nil;
}

static NSString *const kTPUnsentKey = @"tp_unsent_messages";
static NSMutableArray<NSString *> *gTPUnsent;

static NSMutableArray<NSString *> *TPUnsentList(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kTPUnsentKey];
        gTPUnsent = [saved isKindOfClass:[NSArray class]] ? [saved mutableCopy] : [NSMutableArray array];
    });
    return gTPUnsent;
}

static NSHashTable<UIView *> *gTPMessageCells;

// Visible message cells are tracked weakly so the "Unsent" label appears immediately, without
// leaving and reopening the chat. The label is shown even after the setting is turned off.
static void TPRefreshMessageCells(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *cell in gTPMessageCells.allObjects) if (cell.window) [cell setNeedsLayout];
    });
}

static void TPRememberUnsent(id deletePayload) {
    id ids = [TPDownloader safeValue:deletePayload key:@"messageAndThreadIds"];
    if (![ids respondsToSelector:@selector(allObjects)] && ![ids isKindOfClass:[NSArray class]]) return;
    NSArray *items = [ids isKindOfClass:[NSArray class]] ? ids : [ids allObjects];
    @synchronized (TPUnsentList()) {
        for (id e in items) {
            NSString *d = [e description];
            if (d.length && ![gTPUnsent containsObject:d]) [gTPUnsent addObject:d];
        }
        while (gTPUnsent.count > 500) [gTPUnsent removeObjectAtIndex:0];
        [[NSUserDefaults standardUserDefaults] setObject:[gTPUnsent copy] forKey:kTPUnsentKey];
    }
    TPRefreshMessageCells();
}

static BOOL TPIsUnsentMessageId(NSString *mid) {
    if (mid.length < 4) return NO;
    @synchronized (TPUnsentList()) {
        for (NSString *d in gTPUnsent) if ([d containsString:mid]) return YES;
    }
    return NO;
}

// Reads a 16-byte Swift String. Only small strings, native strings and bridged NSStrings are
// accepted, and every address is checked before it is read.
static NSString *TPReadSwiftString(const uint8_t *p) {
    if (!p) return nil;
    uint64_t w0, w1;
    memcpy(&w0, p, 8); memcpy(&w1, p + 8, 8);
    if (w1 & (1ULL << 61)) {
        NSUInteger n = (w1 >> 56) & 0xF;
        if (n > 15) return nil;
        char buf[16]; memcpy(buf, p, 16);
        return [[NSString alloc] initWithBytes:buf length:n encoding:NSUTF8StringEncoding];
    }
    uintptr_t addr = (uintptr_t)(w1 & 0x0FFFFFFFFFFFFFFFULL);
    if (!addr || !malloc_zone_from_ptr((const void *)addr)) return nil;
    if ((w1 >> 60) == 0x4) {
        id obj = (__bridge id)(void *)addr;
        return [obj isKindOfClass:[NSString class]] ? obj : nil;
    }
    if ((w1 >> 60) != 0) return nil;
    NSUInteger n = (NSUInteger)(w0 & 0x0000FFFFFFFFFFFFULL);
    if (n == 0 || n > 512 || malloc_size((const void *)addr) < 32 + n) return nil;
    return [[NSString alloc] initWithBytes:(const void *)(addr + 32) length:n encoding:NSUTF8StringEncoding];
}

static NSString *TPMessageIdOfCell(UIView *cell) {
    uint8_t *m = TPIvarAddress(cell, "model");
    if (!m) return nil;
    uintptr_t thread; memcpy(&thread, m, 8);
    if (!thread) return nil;
    return TPReadSwiftString(m + 8);
}

static const void *kTPUnsentLabelKey = &kTPUnsentLabelKey;

static void TPUpdateUnsentLabel(UIView *cell) {
    UILabel *label = objc_getAssociatedObject(cell, kTPUnsentLabelKey);
    NSString *mid = TPMessageIdOfCell(cell);
    BOOL show = mid && TPIsUnsentMessageId(mid);
    if (!show) { label.hidden = YES; return; }
    uint8_t *slot = TPIvarAddress(cell, "$__lazy_storage_$_messageContentContainerView");
    UIView *bubble = nil;
    if (slot) { uintptr_t v; memcpy(&v, slot, 8); bubble = v ? (__bridge UIView *)(void *)v : nil; }
    if (![bubble isKindOfClass:[UIView class]] || !bubble.superview) return;
    if (!label) {
        label = [UILabel new];
        label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        label.textColor = UIColor.systemRedColor;
        label.text = TPL(@"Unsent");
        [label sizeToFit];
        objc_setAssociatedObject(cell, kTPUnsentLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *host = ((UICollectionViewCell *)cell).contentView;
    if (label.superview != host) [host addSubview:label];
    CGRect b = [bubble convertRect:bubble.bounds toView:host];
    CGSize s = label.bounds.size;
    BOOL bubbleOnLeft = CGRectGetMidX(b) < host.bounds.size.width / 2;
    CGFloat x = bubbleOnLeft ? CGRectGetMaxX(b) + 6 : CGRectGetMinX(b) - 6 - s.width;
    label.frame = CGRectMake(x, CGRectGetMaxY(b) - s.height - 4, s.width, s.height);
    label.hidden = NO;
}

%group KeepUnsent
%hook MDCoreDeltaApplyingBridge
- (id)initWithWrappedTypeName:(id)name dataRequestHandler:(id)a mutationCommandsHandler:(id)b queueInfoHandler:(id)c {
    id me = %orig;
    if (me && name) objc_setAssociatedObject(me, kTPApplierNameKey, name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return me;
}
- (id)mutationCommandsForDeltaWithRequestedState:(id)state currentUserFbid:(id)fbid shouldFallbackToInboxResnapshotOnDeltaHandlingError:(BOOL)fallback {
    id r = %orig;
    if (![TPPrefs boolForKey:TPKeyKeepUnsent]) return r;
    NSString *name = objc_getAssociatedObject(self, kTPApplierNameKey);
    if (![name isKindOfClass:[NSString class]] || ![name containsString:@"DeleteMessage"]) return r;
    Class resultCls = objc_getClass("MDCoreDeltaApplicationResult");
    Ivar iv = resultCls && [r isKindOfClass:resultCls] ? class_getInstanceVariable(resultCls, "_mutationCommands_commands") : NULL;
    NSArray *cmds = iv ? object_getIvar(r, iv) : nil;
    if (![cmds isKindOfClass:[NSArray class]]) return r;
    NSMutableArray *kept = [NSMutableArray array];
    for (id cmd in cmds) {
        id payload = TPDeleteCommandPayload(cmd);
        if (!payload) { [kept addObject:cmd]; continue; }
        if (payload != (id)kCFNull) TPRememberUnsent(payload);
    }
    if (kept.count == cmds.count) return r;
    SEL make = NSSelectorFromString(@"mutationCommandsWithCommands:");
    if (![resultCls respondsToSelector:make]) return r;
    TPDebug(TPL(@"Unsent message kept"));
    return ((id (*)(id, SEL, id))objc_msgSend)(resultCls, make, kept);
}
%end

%hook _TtC21BCNSlideMessageListUI27BCNSlideMessageListViewCell
- (void)layoutSubviews {
    %orig;
    if (!gTPMessageCells) gTPMessageCells = [NSHashTable weakObjectsHashTable];
    [gTPMessageCells addObject:(UIView *)self];
    TPUpdateUnsentLabel((UIView *)self);
}
%end
%end

%ctor {
    @autoreleasepool {
        TPSideloadFixInstall();
        for (NSString *old in @[@"tp_last_logout", @"tp_logout_history", @"tp_logout_keychain"])
            [[TPPrefs defaults] removeObjectForKey:old];
        %init(Ads);
        %init(Tracking);
        %init(Download);
        %init(Images);
        %init(VideoSettings);
        %init(Time);
        %init(Interactions);
        gTPProfileHeaderClass = objc_getClass("_TtC10BCNProfile20BCNProfileHeaderView");
        %init(Avatar);
        %init(AccountSwitch);
        %init(KeepFeed);
        gTPMainFeedClass = objc_getClass("_TtC11BCNMainFeed25BCNMainFeedViewController");
        %init(HomeFeedControls);
        gTPUserRecsClass = objc_getClass("_TtC22BCNUserRecommendations36BCNUserRecommendationsViewController");
        %init(HideFollowSuggest);
        %init(PinTabBar);
        %init(HideFeedSuggestions);
        %init(BlockScreenshotDetection);
        %init(BlockAnalytics);
        TPInstallAnalyticsUploadBlock();
        %init(ExternalBrowser);
        %init(HideIGButton);
        %init(HomeLongPress);
        %init(NoSeen);
        %init(KeepUnsent);
        %init(NoTyping);
        %init(Menu);

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            gTPBackgroundedAt = CFAbsoluteTimeGetCurrent();
            [[TPPrefs defaults] setObject:TPSideloadFixStats() forKey:@"tp_sf_last_stats"];
            [[TPPrefs defaults] setInteger:gTPAnalyticsDropped forKey:@"tp_analytics_last_dropped"];
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                TPCheckClipboard();
            });
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSString *last = [[TPPrefs defaults] stringForKey:@"tp_sf_last_stats"];
                NSString *msg = [NSString stringWithFormat:@"%@: %@", TPL(@"Sideload Compatibility Fix"), TPSideloadFixStatus()];
                if (last.length) msg = [msg stringByAppendingFormat:@"\n%@: %@", TPL(@"Last session"), last];
                if ([TPPrefs boolForKey:TPKeyBlockAnalytics])
                    msg = [msg stringByAppendingFormat:@"\n%@: %ld", TPL(@"Analytics blocked last session"),
                           (long)[[TPPrefs defaults] integerForKey:@"tp_analytics_last_dropped"]];
                if ([TPPrefs boolForKey:TPKeyDebugToast]) [TPHUD toast:[@"[TP] " stringByAppendingString:msg]];
            });
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            [TPWelcomeViewController presentIfNeeded];
        }];
    }
}
