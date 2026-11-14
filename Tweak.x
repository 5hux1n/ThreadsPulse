// ThreadsPulse — Threads (com.burbn.barcelona) 增強插件
//
// 所有類別與方法名稱皆取自 Threads 主程式的 class-dump 標頭。
// Threads 更新後若方法改名，對應 hook 會「靜默失效」（不會崩潰），
// 請在設定選單開啟「除錯提示」確認哪一項還有作用。
//
// 重要：Threads 的許多類別是 Swift 類別，標頭只有名字沒有定義，
// 所以對 `self` 呼叫方法時一律先轉型成 (id) 或 (UIView *)。

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

@interface NSObject (TPDecl)
- (void)tp_threeFingerLongPress:(id)gesture;
// Threads 內部類別沒有可用的標頭，先宣告會用到的方法，讓編譯器認得
- (void)setPlaybackSpeed:(float)speed;
- (BOOL)isPlaying;
- (void)play;          // FNFPlayer
- (void)pause;
- (void)setVolume:(float)volume rampTime:(float)time;   // FNFPlayer
- (id)videoPlayer;     // Swift 外層 IGVideoPlayer → 內層 IGFNFVideoPlayer
// IGPhoto：依寬度取得對應尺寸的圖片網址（回傳 IGImageURL）
- (id)imageURLForWidth:(double)width;
@end

static NSURL *TPBestImageURLFromPhoto(id photo);   // 定義在後面：從 IGPhoto 的版本清單挑最大張
static NSMutableString *gTPSizeLog;                 // 除錯：每張照片有哪些尺寸、挑了哪個
static NSInteger gTPSizeIndex;

static NSInteger gTPOwnPasteboardChange = -1;     // Threads 自己複製時的剪貼簿版本（不提示）

#pragma mark - 共用小工具

/// 不節流的除錯提示（診斷一連串步驟時用，避免被 2 秒節流吃掉）
static void TPDebugNow(NSString *msg) {
    if (![TPPrefs boolForKey:TPKeyDebugToast]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [TPHUD toast:[@"[TP] " stringByAppendingString:msg]]; });
}

static void TPDebug(NSString *msg) {
    if (![TPPrefs boolForKey:TPKeyDebugToast]) return;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last < 2.0) return;           // 節流，避免洗版
    last = now;
    [TPHUD toast:[@"[TP] " stringByAppendingString:msg]];
}

/// 往下找第一個屬於 cls 的 view（包含 root 自己），最多找 maxDepth 層
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


#pragma mark - 1) 去廣告
// 分三層攔截：要求廣告 → 收到廣告 → 插入廣告。任一層生效就看不到廣告。

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

%end // group Ads

#pragma mark - 2) 移除網址追蹤碼

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

%end // group Tracking

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

/// 動態串文裡的媒體由「串文層級的批次按鈕」負責，單支影片／單張圖片上不再重複放按鈕
static BOOL TPInsideFeedMediaCell(UIView *v) {
    Class c = TPFeedMediaCellClass();
    if (!c) return NO;
    for (UIView *s = v.superview; s; s = s.superview) if ([s isKindOfClass:c]) return YES;
    return NO;
}

#pragma mark - 3) 影片下載按鈕

static const void *kTPButtonKey = &kTPButtonKey;
static const void *kTPPlayerKey = &kTPPlayerKey;

static const void *kTPPlayerViewKey = &kTPPlayerViewKey;

/// 弱參照容器：讓播放器記得自己的畫面，又不會互相保留造成記憶體洩漏
@interface TPWeakBox : NSObject
@property (nonatomic, weak) id object;
@end
@implementation TPWeakBox
@end

static void TPPauseIfHeld(id player);   // 停用自動播放：定義在後面

/// 影片畫面拿到的是 Swift 外層播放器；真正負責播放的是它裡面的 IGFNFVideoPlayer
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
            // 先從影片附近的資料物件找網址（影片沒播放過也找得到），找不到才問播放器
            NSURL *url = [TPDownloader bestVideoURLNearView:v];
            if (!url) url = [TPDownloader bestURLFromVideoView:v player:player];
            if (!url) {
                if ([TPPrefs boolForKey:TPKeyDebugToast])
                    [TPDownloader showReport:[TPDownloader debugReportForVideoView:v player:player]];
                else
                    [TPHUD toast:TPL(@"No download link found. Play the video for a moment, then try again.")];
                return;
            }
            [TPDownloader downloadVideoURL:url];
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

// IGVideoView 是 Swift 類別：Threads 內部直接呼叫它的方法不會經過 ObjC，
// 所以改掛 UIKit 一定會用 ObjC 呼叫的 didMoveToWindow / layoutSubviews，
// 並從播放器的 ObjC 回呼記下播放器物件（影片網址等按下按鈕時才去取）。
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

%end // group Download

#pragma mark - 4) 圖片／影片：串文一鍵批次下載

static const void *kTPImgBtnKey   = &kTPImgBtnKey;
static const void *kTPBatchBtnKey = &kTPBatchBtnKey;

/// 在 root 底下收集已載入圖片的 UIImageView（IGImageView 是它的子類別）
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

/// 從 IGImageView 取出目前顯示的圖片網址：imageSpecifier → _remoteImage_imageURL → url
static NSURL *TPURLForImageView(UIImageView *iv) {
    id spec = [TPDownloader safeValue:iv key:@"imageSpecifier"];
    if (!spec) return nil;
    id imgURL = [TPDownloader ivarValue:spec name:@"_remoteImage_imageURL"];
    if (!imgURL) imgURL = [TPDownloader ivarValue:spec name:@"_prefetchedAdaptiveRemoteImageDEPRECATED_imageURL"];
    id u = [TPDownloader safeValue:imgURL key:@"url"];
    return [u isKindOfClass:[NSURL class]] ? u : nil;
}

/// 用檔名（不含副檔名與縮放參數）當作去重 key：同一張圖的不同尺寸、輪播重複的項目都會被合併
static NSString *TPDedupeKey(NSURL *u) {
    return [[u.path lastPathComponent] stringByDeletingPathExtension];
}

/// 從 IGMedia / IGBaseMedia（cell 的 mediaFragment 就是它）取出影片網址。
/// 這條路不需要影片播放過：IGMedia.video → IGVideo.videoVersions 已經帶有完整網址。
static NSURL *TPVideoURLFromMedia(id media) {
    if (!media) return nil;
    for (NSString *key in @[@"video", @"computedVideo"]) {
        id video = [TPDownloader safeValue:media key:key];
        NSURL *u = [TPDownloader bestURLFromObject:video];
        if (u) return u;
    }
    return [TPDownloader bestURLFromObject:media];
}

/// 從 IGMedia / IGBaseMedia 取出圖片網址：media.photo → imageURLForWidth:(原圖寬度) → IGImageURL.url
/// 這條路不需要圖片已經顯示在畫面上，批次下載時捲過去還沒載入的圖片也拿得到。
static NSURL *TPImageURLFromMedia(id media) {
    if (!media) return nil;
    for (NSString *key in @[@"photo", @"computedPhoto"]) {
        id photo = [TPDownloader safeValue:media key:key];
        NSURL *best = TPBestImageURLFromPhoto(photo);
        if (best) return best;
        if (!photo || ![photo respondsToSelector:@selector(imageURLForWidth:)]) continue;

        double w = 4096;                                       // 預設要一張夠大的
        id sizeVal = [TPDownloader safeValue:photo key:@"size"];
        if ([sizeVal isKindOfClass:[NSValue class]]) {
            CGSize sz = [(NSValue *)sizeVal CGSizeValue];
            if (sz.width > 0) w = sz.width;                    // 原圖寬度 → 最大尺寸
        }
        id imgURL = nil;
        @try { imgURL = [photo imageURLForWidth:w]; } @catch (__unused id e) {}
        id u = [imgURL isKindOfClass:[NSURL class]] ? imgURL : [TPDownloader safeValue:imgURL key:@"url"];
        if ([u isKindOfClass:[NSURL class]]) return u;
    }
    return nil;
}

/// 解析串文媒體區裡的「單一項目」(圖片 cell 或影片 cell)。回傳 nil 表示這不是媒體項目。
/// 影片取不到網址時回傳 @{@"video":@YES, @"failed":@YES}。
static NSDictionary *TPItemForMediaCell(UIView *cell) {
    id fragment = [TPDownloader ivarValue:cell name:@"mediaFragment"];   // 項目自己的媒體資料（IGMedia）

    // 判斷是不是影片：看 cell 類別，或裡面有沒有 IGVideoView
    // （影片還沒開始準備時，IGVideoView 可能尚未建立，不能只靠它判斷，否則會誤抓縮圖）
    static Class videoCellClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ videoCellClass = NSClassFromString(@"_TtC16BCNFeedMediaCell21BCNFeedMediaVideoCell"); });
    UIView *vv = TPFindView(cell, TPVideoViewClass(), 30);
    BOOL isVideo = vv != nil || (videoCellClass && [cell isKindOfClass:videoCellClass]);

    if (isVideo) {
        NSURL *url = nil;
        if (vv) {                                                      // 1) 已播放過：直接從播放器取
            id player = objc_getAssociatedObject(vv, kTPPlayerKey);
            url = [TPDownloader bestURLFromVideoView:vv player:player];
        }
        if (!url) url = TPVideoURLFromMedia(fragment);                 // 2) 沒播放過：從媒體資料取
        if (!url && fragment) url = [TPDownloader bestVideoURLHarvestedFromObject:fragment];   // 3) 最後手段：搜尋物件圖
        if (!url) {
            TPDebug([NSString stringWithFormat:@"video fragment: %@", fragment ? NSStringFromClass([fragment class]) : @"nil"]);
            return @{ @"video": @YES, @"failed": @YES };
        }
        return @{ @"video": @YES, @"urls": @[url], @"key": TPDedupeKey(url) };
    }

    UIImageView *iv = TPLargestImageView(cell);
    NSURL *url = TPImageURLFromMedia(fragment);                        // 1) 資料模型（最完整，不用等載入）
    if (!url && iv) url = TPURLForImageView(iv);                       // 2) 畫面上已載入的圖片
    if (!url && fragment) url = [TPDownloader bestImageURLHarvestedFromObject:fragment];   // 3) 最後手段
    if (!url && !iv.image) {
        TPDebug([NSString stringWithFormat:@"photo fragment: %@", fragment ? NSStringFromClass([fragment class]) : @"nil"]);
        return nil;
    }

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"video"] = @NO;
    d[@"urls"] = url ? @[url] : @[];
    if (iv.image) d[@"image"] = iv.image;            // 網址全失敗時，退而存畫面上已載入的那張
    d[@"key"] = url ? TPDedupeKey(url) : [NSString stringWithFormat:@"img%p", iv.image];
    return d;
}


/// 單一媒體（IGMedia）→ 下載項目。影片取不到網址時回傳 failed。
static NSDictionary *TPItemForMedia(id media) {
    if (!media) return nil;
    id video = [TPDownloader safeValue:media key:@"video"];
    if (!video) video = [TPDownloader safeValue:media key:@"computedVideo"];
    if (video) {
        NSURL *u = TPVideoURLFromMedia(media);
        if (!u) u = [TPDownloader bestVideoURLHarvestedFromObject:media];
        if (!u) return @{ @"video": @YES, @"failed": @YES };
        return @{ @"video": @YES, @"urls": @[u], @"key": TPDedupeKey(u) };
    }
    NSURL *u = TPImageURLFromMedia(media);
    if (!u) u = [TPDownloader bestImageURLHarvestedFromObject:media];
    if (!u) return @{ @"video": @NO, @"failed": @YES };
    return @{ @"video": @NO, @"urls": (u ? @[u] : @[]), @"key": TPDedupeKey(u) };
}

static NSString *gTPLastMediaDiag;     // 最近一次取不到網址的診斷資訊（除錯提示開啟時會顯示）

/// 收集 root 底下所有輪播項目 cell（帶有 mediaFragment 實例變數的 view）
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

/// 一個取不到網址的項目 → 診斷文字
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

/// 直接從串文的資料模型取出「所有」媒體：parentMediaFragment.carouselMedia（完整的輪播清單）。
/// 不需要捲動，也不受輪播 cell 重複使用的影響。資料模型取不到網址的影片，再改用畫面上該項目的播放器。
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
    if (![children isKindOfClass:[NSArray class]] || !children.count) children = frag ? @[frag] : @[];   // 單一媒體串文

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableString *diag = [NSMutableString string];
    NSInteger idx = 0;
    for (id child in children) {
        NSDictionary *d = TPItemForMedia(child);

        // 資料模型拿不到 → 找畫面上「同一個項目」的 cell，改從它的播放器拿
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

#pragma mark   └ 從輪播 cell 的 items（BCNFeedMediaViewModel）直接讀出每一項的 IGPhoto / IGVideo

/// IGPhoto／IGVideo 以及它們所有子類別的 class 指標集合，用來「安全地」辨識從記憶體讀到的指標
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

/// 把 Swift enum 記憶體裡的一個 word 當成物件指標，但「只有」確認它真的是 allowed 裡的類別才回傳。
/// 步驟：去掉 Swift 可能藏在高位的標記 → 確認是 heap 配置（讀取不會閃退）→ 確認 class 在白名單內。
static id TPObjectFromWord(uintptr_t w, NSSet<NSValue *> *allowed) {
    uintptr_t p = w & 0x0000000FFFFFFFF8ULL;
    if (p < 0x100000000ULL) return nil;
    if (!malloc_zone_from_ptr((const void *)p)) return nil;
    uintptr_t isa = *(const uintptr_t *)p & 0x0000000FFFFFFFF8ULL;   // arm64 的 isa 遮罩：直接讀位元，不對未確認的指標做任何物件操作
    if (![allowed containsObject:[NSValue valueWithPointer:(const void *)isa]]) return nil;
    return (__bridge id)(void *)p;
}

/// 取得物件某個實例變數的原始記憶體位址（給 Swift 的 enum / Int 這類非物件欄位用）
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

/// 從 IGPhoto 內部的完整版本清單（_originalImageVersions／_processedImageVersions）挑「面積最大」的網址。
/// 清單裡每一項是 IGImageURL，本身就有 width／height 屬性。
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
            if (w <= 0 || h <= 0) {                                    // 備援：IGImageURLInfo
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

/// 輪播 cell 本身的 items 陣列（Threads 用它來顯示輪播，數量一定完整）
static NSArray<NSDictionary *> *TPCollectPostMediaFromViewModels(UIView *cellRoot) {
    id vms = [TPDownloader ivarValue:cellRoot name:@"items"];      // Swift [BCNFeedMediaViewModel]（可當 NSArray 用）
    if (![vms isKindOfClass:[NSArray class]] || ![(NSArray *)vms count]) return nil;

    NSMutableArray<UIView *> *itemCells = [NSMutableArray array];   // 畫面上的輪播 cell，給影片備援用
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
            if (!u) {
                // 資料裡沒有直連網址 → 找畫面上同一個位置的 cell，改從它的播放器拿
                for (UIView *c in itemCells) {
                    uint8_t *mi = TPIvarAddress(c, "mediaIndex");             // Swift Int?：8 bytes 數值 + 1 byte 是否為 nil
                    if (!mi || mi[8] != 0 || *(NSInteger *)mi != idx) continue;
                    NSDictionary *fromCell = TPItemForMediaCell(c);
                    if (fromCell && ![fromCell[@"failed"] boolValue]) d = fromCell;
                    break;
                }
                if (!d) { d = @{ @"video": @YES, @"failed": @YES }; [diag appendString:TPDiagForVideo(video, idx)]; }
            } else {
                d = @{ @"video": @YES, @"urls": @[u], @"key": TPDedupeKey(u) };
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
    if (!recognized) return nil;                                    // 一項都認不出來 → 交給其他方法

    gTPLastMediaDiag = diag.length
        ? [NSString stringWithFormat:@"ThreadsPulse %@ [items]\nitems: %lu\n\n%@", TP_VERSION, (unsigned long)[(NSArray *)vms count], diag]
        : nil;
    TPDebug([NSString stringWithFormat:TPL(@"Found %ld of %ld items"), (long)items.count, (long)[(NSArray *)vms count]]);
    return items;
}

/// 先用輪播 cell 的 items（完整、快）；拿不到才改用串文資料模型
static NSArray<NSDictionary *> *TPCollectPostMedia(UIView *cellRoot) {
    NSArray *items = TPCollectPostMediaFromViewModels(cellRoot);
    return items.count ? items : TPCollectPostMediaFromModel(cellRoot);
}

#pragma mark   └ 原始尺寸：從 threads.com 網頁版取得 Meta 保存的最大張

/// 媒體 pk（數字）→ 串文代碼（Instagram／Threads 的 base64 字母表）
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

/// 盡力找出這則串文的代碼：媒體資料的 code → 輪播父項目 → 父項目 pk 換算 → 同一則串文的按讚列 → 單一媒體的 mediaID 換算
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
        if (!parent) { code = TPCodeFromMedia(frag); if (code) return code; }   // 單一媒體：frag 就是串文本身
    }

    // 同一則串文的其他 cell（例如按讚列）帶有串文資料
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

    // 只有一個媒體時，它的 mediaID 就是串文 ID
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

/// 解析網頁：找出所有 {"url":"https://…","width":N,"height":N} 候選，依檔名取面積最大的那個
/// 把網頁裡可能被跳脫一或多層的 JSON 還原：\\\" → "、\/ → /、\u0026 → &
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

/// 網頁內容摘要（除錯用）：關鍵字出現次數＋第一個圖片網址附近的片段
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
        if ([path hasSuffix:@".mp4"]) continue;                                            // 影片不算
        if ([path containsString:@"-19/"] != avatars) continue;                              // 「-19/」是大頭貼的路徑特徵
        double a = [[obj substringWithRange:[w rangeAtIndex:1]] doubleValue] * [[obj substringWithRange:[h rangeAtIndex:1]] doubleValue];
        count++;
        NSString *key = TPDedupeKey(url);
        if (a > [area[key] doubleValue]) { area[key] = @(a); best[key] = url; }
    }
    // og:image 預覽圖（有些網頁只有這個）
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

/// 把 items 裡的圖片網址換成網頁版的最大張（原本的網址留作備援），完成後呼叫 done
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

/// 讀 page 網頁，依檔名把 items 裡的圖片換成網頁版的最大張（原本的網址留作備援）
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

    // attempt 會在完成時自己設成 nil，避免區塊互相持有造成記憶體不釋放
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

            if (!originals.count && idx + 1 < agents.count) {        // 這個身分沒拿到 → 換下一個
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
                if (!orig && !avatars && originals.count == 1 && items.count == 1) orig = originals.allValues.firstObject;   // 單張：og:image 檔名可能不同
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

/// filter：0 = 全部，1 = 只要圖片，2 = 只要影片
static void TPBatchDownload(UIView *cell, NSInteger filter) {
    BOOL debug = [TPPrefs boolForKey:TPKeyDebugToast];
    gTPSizeLog = debug ? [NSMutableString string] : nil;
    gTPSizeIndex = 0;
    NSArray<NSDictionary *> *raw = TPCollectPostMedia(cell);
    if (gTPSizeLog.length) [TPDownloader setPendingReport:[@"[photo sizes in app]\n" stringByAppendingString:gTPSizeLog]];
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
        [TPDownloader showReport:gTPLastMediaDiag];            // 除錯用：列出哪些項目、為什麼取不到網址
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
            if (wc) TPBatchDownload(wc, 0);                 // 點一下：整則串文全部下載
        } menuItems:@[all, imgs, vids]];                  // 長按：只下載圖片／只下載影片
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

// ---- 全螢幕檢視（燈箱）：單張圖片按鈕。點一下＝這張；長按＝這張／已載入的全部 ----

/// IGMedia 及其子類別（給 Swift enum 記憶體掃描用）
static NSSet<NSValue *> *TPMediaClasses(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = TPClassFamily(@"IGMedia"); });
    return s;
}

/// 全螢幕圖片：從 cell 的 postItem、或全螢幕畫面存的整則串文，找出串文代碼
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

    // 全螢幕畫面 BCNLightboxViewController.content.body（Swift enum，.post 的第一個值是整則串文的 IGMedia）
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

    // 只下載這張時，用 cell 的 postItem.photo 挑 App 裡最大的版本
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
    b.frame = CGRectMake(CGRectGetMaxX(r) - d - 10, CGRectGetMaxY(r) - d - 10, d, d);   // 圖片右下角，避開上方控制列
    if (host.subviews.lastObject != b) [host bringSubviewToFront:b];
}

%group Images

// 動態串文：整則串文一顆批次按鈕
%hook _TtC16BCNFeedMediaCell16BCNFeedMediaCell
- (void)layoutSubviews { %orig; TPEnsureBatchButton((UIView *)self); }
- (void)didMoveToWindow { %orig; TPEnsureBatchButton((UIView *)self); }
%end

// 全螢幕檢視
%hook _TtC11BCNLightbox20BCNLightboxPhotoCell
- (void)layoutSubviews { %orig; TPEnsureLightboxButton((UIView *)self); }
%end

%end // group Images

#pragma mark - 5) 影片預設倍速

static float TPSpeedForIndex(NSInteger i) {
    static const float table[] = {1.0f, 1.25f, 1.5f, 2.0f};
    return (i >= 0 && i <= 3) ? table[i] : 1.0f;
}

static const void *kTPPlayerInitKey = &kTPPlayerInitKey;

#pragma mark   └ 停用自動播放

// 做法：動態裡的影片滑進畫面時，讓 Threads 照常開始播放（聲音圖示等介面才會出現），
// 但底層 FNFPlayer 先以音量 0 試播到第一格就停住，之後的播放要求一律忽略；點一下影片才放開。
// 開始播放後同一個播放器不再按住，直到它被停止（滑走、cell 重用）。不在動態裡的影片（例如全螢幕）照常播放。
static const void *kTPUserStartedKey = &kTPUserStartedKey;
static const void *kTPTouchStartKey  = &kTPTouchStartKey;
static const void *kTPHeldKey = &kTPHeldKey;   // 自動播放被「按住」：Threads 照常開始播放（喇叭圖示等介面才會出現），但底層播放器不准動
static CFAbsoluteTime gTPLastTapAt = 0;

/// IGFNFVideoPlayer 裡真正出聲出畫面的 FNFPlayer
static id TPFNFPlayer(id inner) {
    Ivar iv = class_getInstanceVariable(object_getClass(inner), "_player");
    return iv ? object_getIvar(inner, iv) : nil;
}

static const void *kTPPrimedKey = &kTPPrimedKey;   // 被按住的底層播放器已經「靜音試播」過一次（讓 Threads 顯示聲音圖示）

static void TPSetHeld(id inner, BOOL held) {
    id v = held ? @YES : nil;
    objc_setAssociatedObject(inner, kTPHeldKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id fnf = TPFNFPlayer(inner);
    if (!fnf) return;
    objc_setAssociatedObject(fnf, kTPHeldKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!held && objc_getAssociatedObject(fnf, kTPPrimedKey)) {   // 放開：音量恢復
        objc_setAssociatedObject(fnf, kTPPrimedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([fnf respondsToSelector:@selector(setVolume:rampTime:)]) [fnf setVolume:1.0f rampTime:0];
    }
}

/// 試播的第一格出來了（Threads 這時會顯示聲音圖示）→ 立刻停住
static void TPPauseIfHeld(id player) {
    id inner = TPInnerPlayer(player);
    if (!inner || !objc_getAssociatedObject(inner, kTPHeldKey)) return;
    id fnf = TPFNFPlayer(inner);
    if ([fnf respondsToSelector:@selector(pause)]) [fnf pause];
}

/// NO = 這次是動態裡的自動播放，要按住
static BOOL TPPlayerMayPlay(id player, long long reason) {
    if (![TPPrefs boolForKey:TPKeyNoAutoplay]) return YES;
    if (objc_getAssociatedObject(player, kTPUserStartedKey)) return YES;
    UIView *view = ((TPWeakBox *)objc_getAssociatedObject(player, kTPPlayerViewKey)).object;
    BOOL tapped = CFAbsoluteTimeGetCurrent() - gTPLastTapAt < 1.5;
    // 還不知道播放器在哪個畫面（剛滑進來時常常還沒對應上）也當作動態裡的影片
    BOOL inFeed = !view || TPInsideFeedMediaCell(view);
    // 只擋「滑進畫面自動播放」(reason 1) 而且在動態裡的影片；其他原因（點擊、全螢幕等）一律放行
    if (reason != 1 || tapped || !inFeed) {
        objc_setAssociatedObject(player, kTPUserStartedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (reason != 1) TPDebug([NSString stringWithFormat:@"%@ (%lld)", TPL(@"Playback allowed"), reason]);
        return YES;
    }
    TPDebug([NSString stringWithFormat:@"%@ (%lld)", TPL(@"Autoplay blocked"), reason]);
    return NO;
}

/// 點了某支被按住的影片：放開底層播放器，影片從第一格開始播
static void TPPlayVideoAtTouch(UITouch *t) {
    UIView *hit = t.view;
    Class vcls = TPVideoViewClass();
    if (!hit || !vcls) return;
    UIView *video = nil;
    for (UIView *v = hit; v; v = v.superview) if ([v isKindOfClass:vcls]) { video = v; break; }
    if (!video) {                                              // 點到影片上的覆蓋層（例如喇叭圖示）：找同一個 cell 裡的影片
        UIView *cell = hit;
        Class cellCls = TPFeedMediaCellClass();
        while (cell && !(cellCls && [cell isKindOfClass:cellCls])) cell = cell.superview;
        if (cell) video = TPFindView(cell, vcls, 30);
    }
    if (!video) return;                                        // 沒點到影片：不是我們的事
    id player = TPInnerPlayer(objc_getAssociatedObject(video, kTPPlayerKey));
    if (!player) { TPDebug(TPL(@"Tap: no video player found")); return; }
    objc_setAssociatedObject(player, kTPUserStartedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!objc_getAssociatedObject(player, kTPHeldKey)) return;   // 沒被按住（已經在播）：交給 Threads 自己處理
    TPSetHeld(player, NO);
    // 等 Threads 先處理完這次點擊（例如切換聲音、開啟全螢幕），再放開
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

// IGFNFVideoPlayer 是 ObjC 類別，Threads 的 Swift 包裝層對它的呼叫會走 ObjC 派送
%hook IGFNFVideoPlayer

- (void)playWithReason:(long long)reason callsiteContext:(id)context {
    BOOL may = TPPlayerMayPlay(self, reason);
    // 自動播放不直接擋掉：讓 Threads 照常走完播放流程（介面、喇叭圖示都正常），只按住底層播放器
    if ([TPPrefs boolForKey:TPKeyNoAutoplay]) TPSetHeld(self, !may);
    // 每個播放器第一次播放時，套用預設倍速
    if (!objc_getAssociatedObject(self, kTPPlayerInitKey)) {
        objc_setAssociatedObject(self, kTPPlayerInitKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        float sp = TPSpeedForIndex([TPPrefs integerForKey:TPKeyPlaySpeed]);
        if (sp != 1.0f) [(id)self setPlaybackSpeed:sp];
    }
    %orig;
}

// 播放器被停止（滑走、cell 重用）：下次又要你點一下才播放
- (void)stopWithReason:(long long)reason callsiteContext:(id)context {
    objc_setAssociatedObject(self, kTPUserStartedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(self, kTPHeldKey)) TPSetHeld(self, NO);
    %orig;
}

// Threads 長按 2 倍速、放開時會設回 1.0 → 改成設回「你選的預設倍速」
- (void)setPlaybackSpeed:(float)speed {
    float def = TPSpeedForIndex([TPPrefs integerForKey:TPKeyPlaySpeed]);
    if (def != 1.0f && speed == 1.0f) speed = def;
    %orig(speed);
}

%end

// 第一次：靜音試播，讓 Threads 跑到「開始播放」顯示聲音圖示，接著在第一格停住；之後的播放一律忽略
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

// 記錄「點擊」：手指放開時移動很少、時間很短才算點擊（滑動不算），只在停用自動播放時才計算
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

%end // group VideoSettings

#pragma mark - 6) 顯示精確時間

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

// Threads 用 NSDate 的 RelativeDate 分類產生「3 小時前」；全部換成絕對時間
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

%end // group Time

#pragma mark - 7) 防誤觸：按讚前確認

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

// Threads 的按讚列是 Swift 的 BCNUFIButton；點擊結束時以 target-action 呼叫這個 ObjC 方法，所以攔得到。
// type 是 BCNUFIButtonType：comment=0、repost=1、like=2 …（無附帶值的 enum，存成 1 byte）
// toggledState 為 YES 代表已按讚
%hook _TtC6BCNUFI12BCNUFIButton
- (void)didEndTappingButtonOnPurpose:(id)sender {
    if (![TPPrefs boolForKey:TPKeyConfirmLike]) { %orig; return; }
    uint8_t *type = TPIvarAddress(self, "type");
    uint8_t *toggled = TPIvarAddress(self, "toggledState");
    BOOL isLike = type && *type == 2;
    BOOL alreadyLiked = toggled && *toggled != 0;
    if (!isLike || alreadyLiked) { %orig; return; }          // 不是愛心，或是收回讚 → 照常
    TPDebug(TPL(@"Like confirmation shown"));
    TPConfirm(TPL(@"Like this post?"), TPL(@"Like"), ^{ %orig; });
}
%end

%end // group Interactions

#pragma mark - 8) 下載大頭貼原圖（全螢幕大頭貼頁面）

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

/// 大頭貼：只用「這個帳號自己」的網址，不再搜尋整份資料（會混到共同追蹤者等其他人的頭像）
static void TPDownloadAvatarFromPictureView(UIView *pic);

static void TPDownloadAvatar(UIViewController *vc) {
    TPDownloadAvatarFromPictureView([TPDownloader ivarValue:vc name:@"profilePictureView"]);
}

/// pic：IGProfilePictureImageView（全螢幕大頭貼頁與個人檔案頁都是這個元件）
static void TPDownloadAvatarFromPictureView(UIView *pic) {
    id profileImage = [TPDownloader safeValue:pic key:@"image"];                    // IGProfileImage
    id user = [TPDownloader ivarValue:profileImage name:@"_profileImageModel_user"];

    // 1) 高解析度大頭貼：user.asIGUserHDProfilePicURLFragment.hdProfilePicUrlInfo.urlString
    NSURL *hd = nil;
    for (NSString *frag in @[@"asIGUserHDProfilePicURLFragment", @"asIGUserHDProfilePicImageURLFragment"]) {
        id info = [TPDownloader safeValue:[TPDownloader safeValue:user key:frag] key:@"hdProfilePicUrlInfo"];
        hd = TPURLFromString([TPDownloader safeValue:info key:@"urlString"]);
        if (hd) break;
    }
    // 2) 畫面上正在顯示的那張
    NSURL *shown = TPURLFromImageSpecifier([TPDownloader ivarValue:profileImage name:@"_imageSpecifier"]);
    // 3) 一般大頭貼網址
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

#pragma mark - 9) 個人檔案頁：長按大頭貼、名稱、用戶名稱、個人簡介

// 長按後跳出選單：儲存大頭貼（下載按鈕開啟時）、複製姓名、複製用戶名稱、複製個人簡介（複製個人檔案資訊開啟時）
static const void *kTPProfilePressKey = &kTPProfilePressKey;
static Class gTPProfileHeaderClass;

/// 往上找到個人檔案頁頂部（BCNProfileHeaderView）
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

/// 個人簡介全文：收合時用完整版本，否則用目前顯示的文字
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

/// 功能關閉時讓手勢直接失敗，Threads 原本的長按（例如個人簡介）就能照常運作
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
        // 個人簡介本身有 Threads 的長按：讓我們的選單優先
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

// 個人檔案頁頂部
%hook _TtC10BCNProfile20BCNProfileHeaderView
- (void)layoutSubviews {
    %orig;
    TPEnsureProfilePress((UIView *)self);
}
%end

%end // group Avatar

#pragma mark - 10) App 內設定選單入口與手勢

static const void *kTPGestureKey3 = &kTPGestureKey3;

/// 三指長按的幫手：記下這次按下去的手指，手勢成立時把這些手指碰到的其他東西全部取消。
///   不這樣做的話，三根手指裡先碰到按鈕或貼文的那一根，放開時還是會觸發它（打開插件後又跳出剛剛按到的東西）
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
    for (UITouch *t in _touches.allObjects)                    // 清掉已經放開的手指
        if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) [_touches removeObject:t];
    [_touches addObject:touch];
    return YES;
}
/// 不擋 Threads 自己的手勢同時辨識（捲動、點按照常），只在三指長按成立時才取消它們
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (void)cancelOtherGesturesExcept:(UIGestureRecognizer *)mine {
    for (UITouch *t in _touches.allObjects) {
        for (UIGestureRecognizer *g in t.gestureRecognizers) {
            if (g == mine || !g.enabled) continue;
            g.enabled = NO;                                    // 關掉再打開：正在進行的辨識會被取消，之後照常運作
            g.enabled = YES;
        }
    }
    [_touches removeAllObjects];
}
@end

%group Menu

// 入口 A：Threads「設定」頁右上角加上「〰 Pulse」按鈕（主題色，與插件設定頁一致）
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
        TPTintEntryButton((UIButton *)i.customView);          // 已經有了：換成目前的主題色
        return;
    }

    UIColor *tint = [TPUI accentIcon];   // 主題色（與設定頁圖示同色）
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
    // 在插件設定頁換主題時，入口按鈕馬上跟著變色
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
    // 入口 B（保底）：三指長按 1 秒 → 插件選單
    if (!objc_getAssociatedObject(self, kTPGestureKey3)) {
        UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tp_threeFingerLongPress:)];
        g.numberOfTouchesRequired = 3;
        g.minimumPressDuration = 1.0;
        g.cancelsTouchesInView = YES;                          // 手勢成立時，取消已經送給按鈕等元件的觸控
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

%end // group Menu

#pragma mark - 11) 剪貼簿連結偵測

static BOOL TPIsThreadsURL(NSURL *u) {
    NSString *host = u.host.lowercaseString;
    if (![u.scheme.lowercaseString hasPrefix:@"http"]) return NO;
    BOOL threads = [host isEqualToString:@"threads.com"] || [host hasSuffix:@".threads.com"] ||
                   [host isEqualToString:@"threads.net"] || [host hasSuffix:@".threads.net"];
    return threads && u.path.length > 1;
}

/// 像從外面點進 Universal Link 一樣交給 Threads，由它自己打開對應的串文、留言或個人檔案
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

/// 使用者按了「開啟」才真正讀剪貼簿（iOS 可能會詢問是否允許貼上）
static void TPOpenClipboardLinkSilently(BOOL silent);
static void TPOpenClipboardLink(void) { TPOpenClipboardLinkSilently(NO); }

/// silent：自動開啟模式下，不是 Threads 連結就安靜略過
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

/// 回到 Threads 時檢查：只判斷「有沒有網址」，不讀內容，所以不會跳出貼上詢問
/// force：切換帳號後使用，略過「同一份剪貼簿只提示一次」與「Threads 自己複製的不提示」
static void TPCheckClipboardForced(BOOL force) {
    if (![TPPrefs boolForKey:TPKeyClipboardLinks]) return;
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSInteger cc = pb.changeCount;
    if (!force) {
        if (cc == gTPOwnPasteboardChange) return;                                // Threads 自己複製的
        if (cc == [TPPrefs integerForKey:@"tp_clip_last_change"]) return;      // 這份剪貼簿已經提示過
    }
    [TPPrefs setInteger:cc forKey:@"tp_clip_last_change"];

    NSSet *patterns = [NSSet setWithObject:UIPasteboardDetectionPatternProbableWebURL];
    [pb detectPatternsForPatterns:patterns completionHandler:^(NSSet *found, NSError *err) {
        if (![found containsObject:UIPasteboardDetectionPatternProbableWebURL]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([TPPrefs integerForKey:TPKeyClipboardMode] == 1) {      // 自動開啟
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

/// 切換帳號後：等新帳號的畫面重建完成再檢查（多個事件只算一次）
static void TPScheduleClipboardCheckAfterSwitch(void) {
    static NSUInteger generation = 0;
    NSUInteger mine = ++generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != generation) return;                // 期間又有新的切換事件，以最後一次為準
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

%end // group AccountSwitch

#pragma mark - 12) 保留首頁動態位置（回到 Threads 不重新整理）

// Threads 從背景回來時，會依「離開了多久」決定要不要重新整理首頁、跳回頂端、甚至切回首頁分頁：
//   ① IGWarmStartListener：applicationWillWarmStartWithTimeIntervalSinceBackgrounded:（首頁、App 主畫面都有實作）
//   ② 首頁自己記錄的 lastBgTime（willEnterForeground 時拿來算離開多久）
//   ③ 伺服器下發的門檻 IGFeedRefreshInstructionsStore（warmStartRefreshInterval 等）
// 做法：在「保留時間」內，讓 Threads 以為只離開了一下子。下拉重新整理、冷啟動都不受影響。

static CFAbsoluteTime gTPBackgroundedAt = 0;   // 進入背景的時間（0 = 這次啟動還沒進過背景）

/// 「保留時間」上限（秒）；不限時間回傳 0
static double TPKeepFeedLimitSeconds(void) {
    switch ([TPPrefs integerForKey:TPKeyKeepFeedLimit]) {
        case 0:  return 10 * 60;
        case 1:  return 30 * 60;
        default: return 0;
    }
}

/// 這次回到前景要不要保留動態。第一次判斷後 10 秒內的檢查都用同一個答案，避免各處結果不一致
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

/// 把 Swift 的 `Date?` ivar 設為現在（Date 是 8 bytes 的 Double，後面 1 byte 是否為 nil：0 = 有值）
static void TPSetOptionalDateNow(id obj, const char *name) {
    Class cls = object_getClass(obj);
    Ivar iv = class_getInstanceVariable(cls, name);
    if (!iv) return;
    ptrdiff_t off = ivar_getOffset(iv);
    // 確認後面還有至少 9 bytes 空間（下一個 ivar 或物件結尾），避免版本變動時寫壞記憶體
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
    double t = CFAbsoluteTimeGetCurrent();      // Foundation.Date 以 2001-01-01 為基準，與 CFAbsoluteTime 相同
    memcpy(p, &t, sizeof(double));
    p[8] = 0;
}

/// 伺服器下發的「離開多久才重新整理」門檻：保留期間改成至少等於保留時間
static NSNumber *TPKeepFeedThreshold(NSNumber *orig) {
    if (![TPPrefs boolForKey:TPKeyKeepFeed]) return orig;
    double limit = TPKeepFeedLimitSeconds();
    if (limit == 0) return @(1.0e9);                             // 不限時間：約 31 年
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

// App 主畫面：離開太久會切回首頁分頁
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

%end // group KeepFeed

#pragma mark - 13) 停用下拉重新整理、點首頁標籤的捲回頂端／重新整理

// 點首頁標籤時，Threads 的判斷是：不在頂端 → 捲回頂端；已在頂端 → 重新整理。
//   新版分頁列（BCNLucentTabBarCoordinator）：重複點同一個分頁時，直接決定要不要讓 Threads 處理這次點擊。
//   舊版分頁列（BCNLegacyTabBarController）：判斷寫在 Swift 裡攔不到，改成記下點擊時間，
//     1 秒內在首頁那一側攔截往上捲動／重新整理。這組 hook 只在第一次點舊版分頁列時才啟用。
static Class gTPMainFeedClass;
static __weak UIViewController *gTPMainFeedVC;     // 最後顯示的首頁（為你推薦／追蹤中各一個）

static CGFloat TPTopOffset(UIScrollView *sv) { return -sv.adjustedContentInset.top; }

/// 這個捲動視圖是不是首頁動態的（往上找第一個 view controller）
static BOOL TPIsMainFeedScrollView(UIScrollView *sv) {
    if (!gTPMainFeedClass) return NO;
    for (UIResponder *r = sv.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:[UIViewController class]]) return [r isKindOfClass:gTPMainFeedClass];
    }
    return NO;
}

/// 目前畫面上的首頁捲動視圖（首頁不在畫面上時回傳 nil）
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

/// 新版分頁列：在首頁時又點了首頁標籤，依開關決定要不要讓 Threads 處理這次點擊
static BOOL TPShouldBlockHomeReselect(void) {
    BOOL noTop = [TPPrefs boolForKey:TPKeyTabNoScrollTop], noRefresh = [TPPrefs boolForKey:TPKeyTabNoRefresh];
    if (!noTop && !noRefresh) return NO;
    UIScrollView *sv = TPVisibleMainFeedScrollView();
    if (!sv) return NO;                                       // 不在首頁：照常
    BOOL atTop = sv.contentOffset.y <= TPTopOffset(sv) + 1.0;
    if (!atTop && noTop)    { TPDebug(TPL(@"Scroll to top blocked"));    return YES; }
    if (atTop && noRefresh) { TPDebug(TPL(@"Home tab refresh blocked")); return YES; }
    return NO;
}

static id TPSelectedTab(id controller) {
    SEL sel = sel_registerName("selectedTab");
    return [controller respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(controller, sel) : nil;
}

// ---- 舊版分頁列的備援：點擊後 1 秒內攔截首頁的往上捲動／重新整理 ----
static CFAbsoluteTime gTPTabTapAt = 0;

static BOOL TPInTabTapWindow(void) {
    return gTPTabTapAt > 0 && CFAbsoluteTimeGetCurrent() - gTPTabTapAt < 1.0;
}

///   不在頂端、往上捲 → 「捲回頂端」
///   已在頂端、再往上捲（露出重新整理圖示）→ 「重新整理」
static BOOL TPShouldBlockFeedScroll(UIScrollView *sv, CGFloat targetY) {
    if (!TPInTabTapWindow() || sv.isTracking) return NO;
    if (targetY >= sv.contentOffset.y - 0.5) return NO;          // 不是往上
    if (!TPIsMainFeedScrollView(sv)) return NO;
    BOOL atTop = sv.contentOffset.y <= TPTopOffset(sv) + 1.0;
    if ((!atTop && [TPPrefs boolForKey:TPKeyTabNoScrollTop]) || (atTop && [TPPrefs boolForKey:TPKeyTabNoRefresh])) {
        TPDebug(TPL(atTop ? @"Home tab refresh blocked" : @"Scroll to top blocked"));
        gTPTabTapAt = CFAbsoluteTimeGetCurrent();             // 動畫還在跑：延長攔截時間
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

// Threads 可能用其中任一種方式捲動
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

%end // group LegacyTabFallback

/// 舊版分頁列被點擊：記下時間；第一次時才啟用上面的備援 hook（新版分頁列的使用者完全不會經過它們）
static void TPMarkLegacyTabTap(void) {
    if (![TPPrefs boolForKey:TPKeyTabNoScrollTop] && ![TPPrefs boolForKey:TPKeyTabNoRefresh]) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ %init(LegacyTabFallback); });
    gTPTabTapAt = CFAbsoluteTimeGetCurrent();
}

/// 長按首頁標籤開啟設定後，手指放開時不要再當成點了首頁（避免捲回頂端／重新整理）
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
// 停用下拉重新整理：使用者拖動時，不讓首頁超過頂端，下拉元件就不會被觸發
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

%end // group HomeFeedControls

#pragma mark - 14) 隱藏「追蹤對象建議」視窗

// 這個視窗是 BCNUserRecommendationsViewController，以底部彈出視窗（sheet）的方式出現。
// 只擋「彈出」的情況；從個人檔案等地方推入（push）的頁面不受影響。
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

// 保險：沒在彈出時攔到（例如包在其他容器裡才加入），出現時若是彈出視窗就直接關掉
%hook _TtC22BCNUserRecommendations36BCNUserRecommendationsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (![TPPrefs boolForKey:TPKeyHideFollowSuggest]) return;
    UIViewController *me = (UIViewController *)self;
    UIViewController *top = me;
    while (top.parentViewController) top = top.parentViewController;
    if (!top.presentingViewController) return;                // 不是彈出視窗（是推入的頁面）：照常顯示
    TPDebug(TPL(@"Follow suggestions hidden"));
    dispatch_async(dispatch_get_main_queue(), ^{ [top dismissViewControllerAnimated:NO completion:nil]; });
}
%end

%end // group HideFollowSuggest

#pragma mark - 15) 固定底部標籤列

// 新版分頁列（BCNLucentTabBarCoordinator）靠 scrollViewDidScroll:／scrollViewDidEndScrolling: 累計捲動距離，
// 決定要不要把標籤列滑出畫面。開啟時不讓它收到捲動事件，標籤列就不會隱藏。
// 另外 iOS 26 原生分頁列的「捲動時縮小」也一併關掉。
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
        ((void (*)(id, SEL, NSInteger))objc_msgSend)((id)self, sel, 1);   // UITabBarMinimizeBehaviorNever
}
%end

%end // group PinTabBar

#pragma mark - 16) 隱藏動態裡的推薦帳號卡片

// 動態裡的推薦都是 IGListKit 的區塊，讓區塊的項目數變成 0 就不會顯示
//   BCNVerticalsSuggestionUnit   ：動態中的「推薦追蹤」橫向卡片
//   BCNAYMFUnit                  ：動態中的「為你推薦」帳號卡片（見下方）
//   BCNInterestFeedSuggestedUnit ：推薦的主題動態／帳號組合
//   BCNSuggestedUser             ：追蹤某人後跳出的推薦（只擋這個情境，surface = followChaining）
//   BCNProfileChainingView       ：個人檔案頁的「為你推薦」（見下方）
%group HideFeedSuggestions

%hook _TtC26BCNVerticalsSuggestionUnit43BCNVerticalsSuggestionUnitSectionController
- (long long)numberOfItems { return [TPPrefs boolForKey:TPKeyHideFeedSuggest] ? 0 : %orig; }
%end

// 「為你推薦」「追蹤建議」帳號卡片（AYMF＝Accounts You May Follow）：首頁動態和追蹤後的推薦歸「推薦帳號」，搜尋頁歸「追蹤建議」，
//   通知、社群頁的同類區塊照常顯示（placement：0 首頁、1 通知、2 搜尋、3 追蹤後推薦、4／5 社群）
%hook _TtC11BCNAYMFUnit24BCNAYMFSectionController
- (long long)numberOfItems {
    if ([TPPrefs boolForKey:TPKeyHideFeedSuggest]) {
        uint8_t *placement = TPIvarAddress(self, "placement");
        if (placement && (*placement == 0 || *placement == 3)) return 0;
    }
    if ([TPPrefs boolForKey:TPKeyHideSearchSuggest]) {               // 搜尋頁的「追蹤建議」另外一個開關
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
        uint8_t *surface = TPIvarAddress(self, "surface");     // 0 提及的使用者、1 追蹤後的推薦、2 社群推薦
        if (surface && *surface == 1) return 0;
    }
    return %orig;
}
%end

// 個人檔案頁的「為你推薦」：自己的個人檔案（新帳號常見），以及在別人個人檔案按追蹤後出現的推薦
// 由 BCNProfileHeaderView 的 showProfileChain 決定要不要顯示 BCNProfileChainingView
%hook _TtC10BCNProfile20BCNProfileHeaderView
- (CGSize)sizeThatFits:(CGSize)fits {
    if ([TPPrefs boolForKey:TPKeyHideFeedSuggest]) {
        uint8_t *show = TPIvarAddress(self, "showProfileChain");
        if (show) *show = 0;                                   // 計算高度時不保留推薦區的空間
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

// 「打造動態消息：你對這則貼文有興趣嗎？」：貼文下方的詢問列（BCNFeedItemSeeMoreSeeLessCell），
//   以及一次問好幾則的詢問區塊（BCNFeedBatchedSeeMoreSeeLessSessionUnit）。詢問列高度變 0 並隱藏
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

%end // group HideFeedSuggestions

#pragma mark - 17) 停用截圖偵測

// Threads 透過 IGScreenshotObserver 得知使用者截圖或錄影（會記錄、跳出分享提示等）
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

%end // group BlockScreenshotDetection

#pragma mark - 18) 阻擋分析回傳

// Threads 的使用紀錄（看了什麼、停留多久、點了什麼、效能數據）都經過 FBAnalyticsCoreLogger 收集，
// 再由 IGAnalyticsNetworkConfigurator 打包上傳。開關打開時：
//   1. 新的紀錄在收集階段就丟掉（不存檔、不即時串流）
//   2. 之前存著還沒傳的紀錄，上傳時改用 Meta 自己的 FBAnalyticsNoOpNetworkConfigurator（不發出網路要求）
// 登入、發文、載入動態等正常的 API 不經過這裡，不受影響。
static int gTPAnalyticsDropped;

// 分析回傳紀錄（設定 › 進階）：只存在記憶體，本次啟動有效，不寫檔、不送出。
// 每筆只記名稱計數；最近 10 筆保留事件物件本身，打開紀錄時才去讀內容，平常幾乎沒有額外負擔。
static NSMutableDictionary<NSString *, NSNumber *> *gTPAnaCounts;
static NSMutableDictionary<NSString *, NSDictionary *> *gTPAnaLast;   // 每種事件只留最新一筆
static NSUInteger gTPAnaTotal;
static const NSUInteger kTPAnaRecentMax = 10;   // 報告列出幾種

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

// 事件名稱的白話說明。Meta 的事件名稱是英文底線命名（例如 feed_item_impression），
// 先查整個名稱（常見事件），查不到就拆成單字逐一翻譯，拼成「動態・項目・曝光」這樣的說明。
// 拆字翻譯是推測，實際意思以內容欄位為準。
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
        // 以下是實際從 Threads 抓到的事件
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
        // 內容與位置
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
        // 動作
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
        // 系統與效能
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

/// 回傳事件的白話說明；認不出任何字就回 nil
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
        // 常見前綴（ig、barcelona、bcn、text_app、fb）只是 Meta 內部代號，不翻
        if ([@[@"ig", @"instagram", @"barcelona", @"bcn", @"xth", @"fb", @"meta", @"textapp", @"ios", @"threads"] containsObject:w]) continue;
        total++;
        NSArray *t = TPAnaWords()[w];
        if (t) { hit++; if (![out.lastObject isEqualToString:t[li]]) [out addObject:t[li]]; }
    }
    if (!hit || hit * 2 < total) return nil;   // 一半以上看不懂就不硬翻，避免誤導
    return [out componentsJoinedByString:zh ? @"・" : @" · "];
}

/// 給設定頁「分析回傳紀錄」用
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
- (BOOL)_captureAnalyticsEventForBatchUpload:(id)event {   // 備援：萬一有路徑直接進批次上傳
    if ([TPPrefs boolForKey:TPKeyBlockAnalytics]) return YES;  // 當作已處理，不存進待上傳的檔案
    return %orig;
}
- (BOOL)_shouldStreamEvent:(id)event {
    if ([TPPrefs boolForKey:TPKeyBlockAnalytics]) return NO;
    return %orig;
}
%end

%end // group BlockAnalytics

// 上傳：參數是大型結構（arm64 以指標傳遞），所以用 (id, SEL, id, void *) 原封不動轉交
typedef BOOL (*TPPerformIMP)(id, SEL, id, void *);
static TPPerformIMP orig_TPAnalyticsPerform, noop_TPAnalyticsPerform;
static BOOL tp_AnalyticsPerform(id self, SEL _cmd, id context, void *requestContext) {
    if (noop_TPAnalyticsPerform && [TPPrefs boolForKey:TPKeyBlockAnalytics])
        return noop_TPAnalyticsPerform(self, _cmd, context, requestContext);
    return orig_TPAnalyticsPerform(self, _cmd, context, requestContext);
}

static void TPInstallAnalyticsUploadBlock(void) {
    SEL sel = NSSelectorFromString(@"performRequestWithContext:requestContext:");
    Class noop = objc_getClass("FBAnalyticsNoOpNetworkConfigurator");
    Class real = objc_getClass("IGAnalyticsNetworkConfigurator");
    Method nm = noop ? class_getInstanceMethod(noop, sel) : NULL;
    Method rm = real ? class_getInstanceMethod(real, sel) : NULL;
    if (!nm || !rm || method_getImplementation(nm) == method_getImplementation(rm)) return;
    // 兩邊型別簽章一致才換，避免 Threads 改版後參數不同
    if (strcmp(method_getTypeEncoding(nm), method_getTypeEncoding(rm)) != 0) return;
    noop_TPAnalyticsPerform = (TPPerformIMP)method_getImplementation(nm);
    orig_TPAnalyticsPerform = (TPPerformIMP)method_setImplementation(rm, (IMP)tp_AnalyticsPerform);
}

#pragma mark - 19) 使用外部瀏覽器開啟連結

/// 要交給外部瀏覽器的網址；Threads 自己的連結或非網頁連結回傳 nil（照原本在 App 裡開）
static NSURL *TPExternalBrowserURL(id url) {
    if (![TPPrefs boolForKey:TPKeyExternalBrowser] || ![url isKindOfClass:[NSURL class]]) return nil;
    NSURL *target = url;
    NSURLComponents *c = [NSURLComponents componentsWithURL:target resolvingAgainstBaseURL:NO];
    if (c && [TPURLCleaner isRedirectHost:c.host]) {             // 先解開 l.threads.com 跳轉包裝，才看得出真正目的地
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

// 串文、個人簡介等處點連結都會經過 BCNLinkHandler（ObjC 協定，所以呼叫走 ObjC 派送）
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

%end // group ExternalBrowser

#pragma mark - 20) 隱藏個人檔案的 Instagram 按鈕、搜尋按鈕

// 個人檔案上方的按鈕都是 BCNProfileViewController 的 lazy 屬性：
//   appSwitcherButton：Instagram 按鈕（點了切換到 Instagram）
//   searchButton     ：搜尋按鈕
static const void *kTPHiddenProfileViewsKey = &kTPHiddenProfileViewsKey;

/// 按鈕外面常包著一層只放它的容器（例如毛玻璃圓底），要把整個容器藏起來，旁邊的按鈕才會靠攏
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
    // 先還原上次藏起來、移過的
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

    // 不在 stack view 裡（Threads 自己算座標）：把同一排的其他按鈕往空位移過去；在 stack view 裡會自動靠攏
    NSMapTable<UIView *, NSNumber *> *shift = [NSMapTable weakToStrongObjectsMapTable];
    for (UIView *slot in slots) {
        if (!slot.superview || [slot.superview isKindOfClass:[UIStackView class]]) continue;
        CGRect f = slot.frame;
        NSMutableArray<UIView *> *left = [NSMutableArray array], *right = [NSMutableArray array];
        CGFloat leftEdge = -CGFLOAT_MAX, rightEdge = CGFLOAT_MAX;
        for (UIView *v in slot.superview.subviews) {
            if ([slots containsObject:v] || v.hidden || v.alpha < 0.01) continue;
            CGRect g = v.frame;
            if (g.size.width > 100 || g.size.height > 100) continue;             // 只動按鈕大小的東西，標題等不碰
            if (CGRectGetMaxY(g) <= CGRectGetMinY(f) || CGRectGetMinY(g) >= CGRectGetMaxY(f)) continue;   // 不同一排
            if (CGRectGetMaxX(g) <= CGRectGetMinX(f) + 1) { [left addObject:v]; leftEdge = MAX(leftEdge, CGRectGetMaxX(g)); }
            else if (CGRectGetMinX(g) >= CGRectGetMaxX(f) - 1) { [right addObject:v]; rightEdge = MIN(rightEdge, CGRectGetMinX(g)); }
        }
        NSArray *movers; CGFloat dx;
        if (left.count) { movers = left; dx = CGRectGetMaxX(f) - leftEdge; }        // 靠右的一排：左邊的往右補
        else if (right.count) { movers = right; dx = CGRectGetMinX(f) - rightEdge; } // 靠左的一排：右邊的往左補
        else continue;
        for (UIView *v in movers) {
            // 藏起來的按鈕相鄰時，每顆算出的距離都已經包含另一顆的空位（計算時兩顆都跳過），取較大的就好，不能相加
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

%end // group HideIGButton

#pragma mark - 21) 長按首頁標籤開啟設定

/// 底部標籤列上的各個標籤按鈕（依 x 座標排好）
static void TPCollectTabButtons(UIView *v, NSMutableArray<UIView *> *out, int depth) {
    if (depth > 8) return;
    for (UIView *s in v.subviews) {
        NSString *cls = NSStringFromClass([s class]);
        if (!s.hidden && s.alpha > 0.01 && ([cls containsString:@"TabButton"] || [cls containsString:@"TabBarButton"])) [out addObject:s];
        else TPCollectTabButtons(s, out, depth + 1);
    }
}

/// 這次長按是不是按在「首頁」標籤（最左邊那個；從右到左的語系是最右邊）上
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
    // 找不到標籤按鈕：把標籤列平均分成幾格估算
    NSUInteger n = [bar isKindOfClass:[UITabBar class]] && ((UITabBar *)bar).items.count ? ((UITabBar *)bar).items.count : 5;
    CGFloat cell = bar.bounds.size.width / n;
    return rtl ? p.x >= bar.bounds.size.width - cell : p.x <= cell;
}

static const void *kTPHomePressKey = &kTPHomePressKey;

%group HomeLongPress

// Threads 長按標籤列的處理（例如長按個人檔案切換帳號）都經過這裡；只攔首頁標籤，其他標籤照常
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
        gTPSuppressTabSelectUntil = CFAbsoluteTimeGetCurrent() + 10;   // 手指還按著：之後的「點選」都不算（最多 10 秒，避免卡住）
        [TPUI hapticLight];
        [TPSettingsViewController present];
        return;
    }
    BOOL mine = objc_getAssociatedObject(press, kTPHomePressKey) != nil;
    if (press.state == UIGestureRecognizerStateEnded || press.state == UIGestureRecognizerStateCancelled
        || press.state == UIGestureRecognizerStateFailed) {
        objc_setAssociatedObject(press, kTPHomePressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (mine) gTPSuppressTabSelectUntil = CFAbsoluteTimeGetCurrent() + 0.6;   // 放開後再擋一下下
    }
    if (!mine) %orig;
}
%end

%end // group HomeLongPress

#pragma mark - 22) 私訊：不顯示看過、不顯示輸入中、防止訊息收回

// 不顯示看過：Threads 標記聊天室已讀時，會用 BCNSlideMDCoreMarkThreadReadMutationBuilder 建立「已讀到某個時間」的請求。
//   把時間改成 0（或已經讓對方看過的位置），伺服器上的已讀位置就不會往前移，對方看不到「看過」；你自己這邊照常當作已經看過。
//   個別聊天室：按右上角的眼睛可以設定這個聊天室照常顯示「看過」，設定會一直保留。
//   回覆訊息時：按下送出就補送一次已讀，訊息等「看過」送到才送出，對方會先看到「看過」再看到你的回覆
static NSString *TPThreadKey(id fbid) {
    if (!fbid) return nil;
    if ([fbid isKindOfClass:[NSString class]]) return fbid;
    if ([fbid isKindOfClass:[NSNumber class]]) return [fbid stringValue];
    id raw = [TPDownloader safeValue:fbid key:@"rawValue"];
    if ([raw isKindOfClass:[NSString class]]) return raw;
    if ([raw isKindOfClass:[NSNumber class]]) return [raw stringValue];
    // 拿不到原始值時，從描述裡取出最長的一串數字（不能用整段描述，裡面有記憶體位址，每個物件都不一樣）
    NSString *best = nil;
    for (NSString *part in [[fbid description] componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]])
        if (part.length > best.length) best = part;
    return best.length >= 6 ? best : [fbid description];
}

// 目前開著的聊天室（標題列在畫面上），以及它是否設定為顯示「看過」
static NSString *gTPOpenChatKey;
static BOOL gTPOpenChatShowsSeen;

static void TPSendSeenNow(NSString *k);
static BOOL TPChatShowsSeen(NSString *key);

static void TPAllowSeenAfterReply(id fbid) {
    NSString *k = TPThreadKey(fbid);
    if (!k.length) return;
    if (TPChatShowsSeen(k)) return;   // 這個聊天室本來就會顯示「看過」
    if (![TPPrefs boolForKey:TPKeySeenOnReply]) return;   // 「回覆後顯示看過」關閉：回覆也不送
    // 1.5 秒內同一個聊天室只算一次
    static NSMutableDictionary<NSString *, NSNumber *> *lastReply;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized ([TPPrefs class]) {
        if (!lastReply) lastReply = [NSMutableDictionary dictionary];
        if (now - [lastReply[k] doubleValue] < 1.5) return;
        lastReply[k] = @(now);
    }
    // 按下送出時就補送已讀（在主執行緒就直接送，要比 MDCoreSendService 排訊息早，那邊才知道要先暫停訊息）
    if ([NSThread isMainThread]) TPSendSeenNow(k);
    else dispatch_async(dispatch_get_main_queue(), ^{ TPSendSeenNow(k); });
}

// 個別聊天室設定：這些聊天室照常送出「看過」（其他聊天室依總開關隱藏）。存在手機裡，重開聊天室或 App 都不會變
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

// 補送已讀（回覆時、打開眼睛時）：照著 Threads 平常送已讀的方式送一次。
//   - 記下每個聊天室上次被擋下的已讀參數（聊天室編號、時間格式）
//   - 記下 Threads 用哪個 GraphQL 服務、哪個方法送出已讀
static const void *kTPMarkReadTag = &kTPMarkReadTag;
static NSMutableDictionary<NSString *, NSDictionary *> *gTPLastReadArgs;
static __weak id gTPGQLService;
static int gTPMarkReadVia;                 // 1 handleWithService、2 handleFiniteWithService、3 initiateRequest、4 initiateFiniteRequest
static BOOL gTPForceSeen;                  // 插件自己補送時，不要被攔下來

static id TPTagMarkRead(id b) {
    if (b) objc_setAssociatedObject(b, kTPMarkReadTag, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return b;
}

static NSMutableDictionary<NSString *, NSNumber *> *gTPSeenSentAt;   // 補送成功的時間，送出訊息時判斷要不要先暫停
// 每個聊天室已經讓對方知道讀到哪個時間（補送或照常送出的）。之後要擋的已讀改送這個時間而不是 0：
//   送 0 會讓伺服器把已讀位置往回退，對方剛看到的「看過」又消失
static NSMutableDictionary<NSString *, NSNumber *> *gTPSeenWatermark;

// 等「看過」送到伺服器才送出的訊息：伺服器一回應就放行，最多等 0.8 秒
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
    // 用 Threads 原本要送的時間（最新一則訊息）；沒有才用現在。用現在的時間伺服器可能不接受
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
    // 伺服器收下「看過」後，稍等 0.15 秒讓它傳到對方，再放行剛才暫停的訊息
    void (^update)(id) = ^(id x) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ TPReleaseHeldMessages(k); });
    };
    void (^failure)(id) = ^(id e) {
        TPDebugNow([NSString stringWithFormat:@"Seen: send failed %@", e]);
        TPReleaseHeldMessages(k);                          // 送不出去也不要卡住訊息
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
    // 記下這個聊天室的已讀參數，回覆時補送用
    NSString *argKey = TPThreadKey(fbid);
    if (argKey.length && fbid) @synchronized ([TPPrefs class]) {
        if (!gTPLastReadArgs) gTPLastReadArgs = [NSMutableDictionary dictionary];
        NSMutableDictionary *d = [@{ @"fbid": fbid, @"otidStr": @([otid isKindOfClass:[NSString class]]),
                                     @"msStr": @([ms isKindOfClass:[NSString class]]) } mutableCopy];
        if (ms && [ms longLongValue] > 0) d[@"ms"] = ms;   // Threads 原本要標記的已讀時間（最新一則訊息的時間）
        gTPLastReadArgs[argKey] = d;
    }
    if (TPChatShowsSeen(TPThreadKey(fbid))) { TPRecordWatermark(argKey, ms); return TPTagMarkRead(%orig); }   // 這個聊天室設定為照常顯示「看過」
    // 保險：開著的聊天室設定為顯示「看過」時也照常送出（萬一兩邊拿到的聊天室編號格式不同）
    if (gTPOpenChatShowsSeen && gTPOpenChatKey.length) {
        NSString *k = TPThreadKey(fbid), *otidKey = TPThreadKey(otid);
        if (!k.length || [k isEqualToString:gTPOpenChatKey] || [gTPOpenChatKey containsString:k] || [k containsString:gTPOpenChatKey]
            || [otidKey isEqualToString:gTPOpenChatKey]) { TPRecordWatermark(argKey, ms); return TPTagMarkRead(%orig); }
        TPDebug([NSString stringWithFormat:@"Seen: %@ ≠ %@", k, gTPOpenChatKey]);
    }
    long long wm;
    @synchronized ([TPPrefs class]) { wm = [gTPSeenWatermark[argKey] longLongValue]; }
    id zero = [ms isKindOfClass:[NSString class]] ? [NSString stringWithFormat:@"%lld", wm] : @(wm);   // 沒送過就是 0
    // Threads 會反覆送出已讀（例如新訊息進來、捲動時），提示同一個聊天室 1 分鐘只顯示一次
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

// 記下 Threads 送出已讀用的服務和方法（補送時照做）
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

// 送出訊息時：Threads 建立「要送出的訊息」（BCNSlideOutgoingMessagePayload）或「對訊息的動作」（回應等，
//   BCNSlideOutgoingMessageUpdatePayload）時就算回覆。不從 MDCoreSendService 判斷：那裡大多是聊天室更新（例如已讀），
//   一進聊天室就會排好幾筆，會被誤當成回覆
// 送出訊息時：如果剛補送「看過」，訊息等伺服器收下「看過」才送（最多 0.8 秒），讓對方先看到「看過」再看到你的回覆
//   （「看過」跟訊息同時到的話，對方畫面上最後一則變成你的訊息，「看過」就沒地方顯示）
%hook MDCoreSendService
- (void)sendMutationWithAppDataModel:(id)model offlineThreadingId:(id)otid optimisticImages:(id)images syncGroupId:(int)group {
    Ivar iv = model && [TPPrefs boolForKey:TPKeyNoSeen] ? class_getInstanceVariable(object_getClass(model), "_outgoingMessagePayload") : NULL;
    id payload = iv ? object_getIvar(model, iv) : nil;
    NSString *k = payload ? TPThreadKey([TPDownloader safeValue:payload key:@"threadFbid"]) : nil;
    BOOL hold = NO;
    if (k.length) @synchronized ([TPPrefs class]) { hold = CFAbsoluteTimeGetCurrent() - [gTPSeenSentAt[k] doubleValue] < 2; }
    if (!hold) { %orig; return; }
    TPDebug(TPL(@"Seen sent first, message follows"));
    // 訊息先暫停，等伺服器收下「看過」再送（直接呼叫原本的方法，不會再進到這裡）
    dispatch_block_t send = ^{ %orig(model, otid, images, group); };
    __block BOOL done = NO;
    dispatch_block_t once = ^{ if (done) return; done = YES; send(); };
    @synchronized ([TPPrefs class]) {
        if (!gTPHeldMessages) gTPHeldMessages = [NSMutableDictionary dictionary];
        if (!gTPHeldMessages[k]) gTPHeldMessages[k] = [NSMutableArray array];
        [gTPHeldMessages[k] addObject:[once copy]];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), once);   // 保險：最多等 0.8 秒
}
%end

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

// 聊天室右上角「…」左邊加一顆眼睛按鈕，個別設定這個聊天室要不要顯示「看過」（設定會保留）：
//   眼睛加斜線（灰）＝不顯示（跟總開關）；眼睛（主題色）＝這個聊天室照常顯示
static const void *kTPSeenButtonKey = &kTPSeenButtonKey;

/// 眼睛按鈕的狀態：顯示「看過」＝眼睛（主題色）；隱藏＝眼睛加斜線（灰）
static void TPSetSeenButtonState(UIButton *b, BOOL showsSeen) {
    [b setImage:[UIImage systemImageNamed:showsSeen ? @"eye" : @"eye.slash"
                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium]]
       forState:UIControlStateNormal];
    b.tintColor = showsSeen ? [TPUI accentIcon] : UIColor.secondaryLabelColor;
    b.accessibilityValue = TPL(showsSeen ? @"This chat shows Seen" : @"This chat hides Seen");
}

/// 聊天室的 BCNSlideMessageListViewController（從按鈕往上找）
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
        // 改成顯示：馬上補送一次已讀，對方立刻看到「看過」
        //   （不假裝離開又回到聊天室：那樣會讓聊天室停止即時接收新訊息）
        if (show) TPSendSeenNow(key);
    }] forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

// 聊天室標題列（BCNSlideMessageListNavBarTitleView）本身就有「…」（moreButton）：
//   在它排版時把眼睛放在「…」左邊，跟著標題列一起出現、一起轉場，不會延遲也不會跑到別的畫面
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
    btn.frame = CGRectMake(CGRectGetMinX(m) - 8 - 36, CGRectGetMidY(m) - 18, 36, 36);   // 「…」左邊，間距 8
    NSString *key = TPChatKeyOf(TPChatViewControllerOf(me));
    BOOL shows = TPChatShowsSeen(key);
    if (key.length && me.window) { gTPOpenChatKey = key; gTPOpenChatShowsSeen = shows; }
    TPSetSeenButtonState(btn, shows);
    btn.hidden = NO;
}
- (void)didMoveToWindow {
    %orig;
    if (!((UIView *)self).window) gTPOpenChatShowsSeen = NO;   // 離開聊天室
}
%end
%end // group NoSeen

// 不顯示輸入中：打字時 Threads 用 BCNTypingIndicatorPublishEventMutationBuilder 送出狀態給對方（1＝輸入中、0＝停止輸入）。
//   開啟時一律改成送 0：請求照常送到正確的聊天室，伺服器只會收到「沒在輸入」，對方就看不到「輸入中…」，
//   也不會因為請求失敗影響聊天室的即時連線（之前改聊天室編號的做法會讓新訊息要進出聊天室才出現）
%group NoTyping
%hook BCNTypingIndicatorPublishEventMutationBuilder
+ (id)builderWithActivityStatus:(id)status threadId:(id)tid {
    if (![TPPrefs boolForKey:TPKeyNoTyping] || ![status isKindOfClass:[NSNumber class]] || [status integerValue] == 0) return %orig;
    static CFAbsoluteTime last;
    if (CFAbsoluteTimeGetCurrent() - last > 60) { last = CFAbsoluteTimeGetCurrent(); TPDebug(TPL(@"Typing status blocked")); }
    return %orig(@0, tid);
}
%end
%end // group NoTyping

// 防止訊息收回：對方收回訊息時，伺服器送來「刪除訊息」的更新，交給 Swift 的 BCNSlideDeleteMessageHandler 處理。
//   它透過 MDCoreDeltaApplyingBridge（ObjC 橋接，建立時帶著處理器的型別名稱）產生要套用到本機資料庫的指令；
//   開關開啟時，把「刪除訊息」處理器產生的刪除指令拿掉，訊息就會留在本機。
static const void *kTPApplierNameKey = &kTPApplierNameKey;

/// MDCoreMutationCommand 是 enum 包裝，用 match 方法判斷是不是「刪除」指令；是的話回傳裡面的 MDCoreDeleteMutationCommand
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

#pragma mark   └ 「已收回」標示

// 被收回的訊息：記下刪除指令裡的訊息識別文字（格式不固定，所以存整段描述，比對時看是否包含訊息 ID）
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

// 畫面上的訊息格子：記下來，對方收回訊息時馬上重新排版，「已收回」立刻出現，不用離開聊天室再回來
static NSHashTable<UIView *> *gTPMessageCells;

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

/// 讀 Swift String（16 bytes）：只接受「短字串」「原生字串」「橋接的 NSString」，讀取前都先確認記憶體位址可用
static NSString *TPReadSwiftString(const uint8_t *p) {
    if (!p) return nil;
    uint64_t w0, w1;
    memcpy(&w0, p, 8); memcpy(&w1, p + 8, 8);
    if (w1 & (1ULL << 61)) {                                   // 短字串：內容就放在這 16 bytes 裡
        NSUInteger n = (w1 >> 56) & 0xF;
        if (n > 15) return nil;
        char buf[16]; memcpy(buf, p, 16);
        return [[NSString alloc] initWithBytes:buf length:n encoding:NSUTF8StringEncoding];
    }
    uintptr_t addr = (uintptr_t)(w1 & 0x0FFFFFFFFFFFFFFFULL);
    if (!addr || !malloc_zone_from_ptr((const void *)addr)) return nil;
    if ((w1 >> 60) == 0x4) {                                  // 橋接的 NSString
        id obj = (__bridge id)(void *)addr;
        return [obj isKindOfClass:[NSString class]] ? obj : nil;
    }
    if ((w1 >> 60) != 0) return nil;                          // 其他形式不處理
    NSUInteger n = (NSUInteger)(w0 & 0x0000FFFFFFFFFFFFULL);   // 原生字串：字元從物件開頭往後 32 bytes
    if (n == 0 || n > 512 || malloc_size((const void *)addr) < 32 + n) return nil;
    return [[NSString alloc] initWithBytes:(const void *)(addr + 32) length:n encoding:NSUTF8StringEncoding];
}

/// 訊息格子的 model（BCNSlideMessageViewModel?）：開頭是 metadata { threadId（物件）, messageId（String）, … }
static NSString *TPMessageIdOfCell(UIView *cell) {
    uint8_t *m = TPIvarAddress(cell, "model");
    if (!m) return nil;
    uintptr_t thread; memcpy(&thread, m, 8);
    if (!thread) return nil;                                   // model 是 nil
    return TPReadSwiftString(m + 8);
}

static const void *kTPUnsentLabelKey = &kTPUnsentLabelKey;

static void TPUpdateUnsentLabel(UIView *cell) {
    UILabel *label = objc_getAssociatedObject(cell, kTPUnsentLabelKey);
    // 不看開關：之前保留下來的訊息，關掉「防止訊息收回」後還是留在聊天室裡，標示也要跟著留著
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
    // 回傳的是 MDCoreDeltaApplicationResult（enum 包裝）；只處理「一組要套用的指令」這一種
    Class resultCls = objc_getClass("MDCoreDeltaApplicationResult");
    Ivar iv = resultCls && [r isKindOfClass:resultCls] ? class_getInstanceVariable(resultCls, "_mutationCommands_commands") : NULL;
    NSArray *cmds = iv ? object_getIvar(r, iv) : nil;
    if (![cmds isKindOfClass:[NSArray class]]) return r;
    NSMutableArray *kept = [NSMutableArray array];
    for (id cmd in cmds) {
        id payload = TPDeleteCommandPayload(cmd);
        if (!payload) { [kept addObject:cmd]; continue; }
        if (payload != (id)kCFNull) TPRememberUnsent(payload);   // 記下來，訊息旁邊才標得出「已收回」
    }
    if (kept.count == cmds.count) return r;               // 沒有刪除指令
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
%end // group KeepUnsent

#pragma mark - 初始化

%ctor {
    @autoreleasepool {
        TPSideloadFixInstall();       // 要在 Threads 開始使用鑰匙圈之前
        for (NSString *old in @[@"tp_last_logout", @"tp_logout_history", @"tp_logout_keychain"])   // 舊版測試用的登出紀錄
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

        // 進入背景時：記下時間（保留首頁動態位置用），並存下這次的鑰匙圈與分析回傳統計（下次開啟時的除錯提示用）
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            gTPBackgroundedAt = CFAbsoluteTimeGetCurrent();
            [[TPPrefs defaults] setObject:TPSideloadFixStats() forKey:@"tp_sf_last_stats"];
            [[TPPrefs defaults] setInteger:gTPAnalyticsDropped forKey:@"tp_analytics_last_dropped"];
        }];

        // 回到 Threads 時檢查剪貼簿裡有沒有連結（稍等一下，讓畫面先就緒）
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                TPCheckClipboard();
            });
        }];

        // 除錯提示：顯示側載相容修正的狀態，以及上次擋下的分析紀錄數
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                // 顯示這次的狀態，以及上次使用期間（進背景前）鑰匙圈的統計
                NSString *last = [[TPPrefs defaults] stringForKey:@"tp_sf_last_stats"];
                NSString *msg = [NSString stringWithFormat:@"%@: %@", TPL(@"Sideload Compatibility Fix"), TPSideloadFixStatus()];
                if (last.length) msg = [msg stringByAppendingFormat:@"\n%@: %@", TPL(@"Last session"), last];
                if ([TPPrefs boolForKey:TPKeyBlockAnalytics])
                    msg = [msg stringByAppendingFormat:@"\n%@: %ld", TPL(@"Analytics blocked last session"),
                           (long)[[TPPrefs defaults] integerForKey:@"tp_analytics_last_dropped"]];
                if ([TPPrefs boolForKey:TPKeyDebugToast]) [TPHUD toast:[@"[TP] " stringByAppendingString:msg]];
            });
        }];

        // 還沒看過歡迎畫面的人，回到 App 時顯示一次（介紹怎麼打開插件設定）
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n) {
            [TPWelcomeViewController presentIfNeeded];
        }];
    }
}
