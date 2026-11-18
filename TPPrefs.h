#import <Foundation/Foundation.h>

extern NSString *const TPKeyBlockAds;
extern NSString *const TPKeyStripTracking;
extern NSString *const TPKeyShowDownloadBtn;
extern NSString *const TPKeyDebugToast;
extern NSString *const TPKeyOriginalAvatar;
extern NSString *const TPKeyOriginalImage;
extern NSString *const TPKeyVideoQuality;   // 0 highest, 1 720p, 2 ask
extern NSString *const TPKeyVideoFormat;    // 0 keep HDR, 1 compatible (H.264 SDR)
extern NSString *const TPKeySaveToAlbum;
extern NSString *const TPKeyParallelDownload;
extern NSString *const TPKeyHideInCaptures;
extern NSString *const TPKeySwipeLockSpeed;
extern NSString *const TPKeyAuthorInfo;
extern NSString *const TPKeyAuthorLocation;
extern NSString *const TPKeyAuthorJoined;
extern NSString *const TPKeyAuthorNewBadge;
extern NSString *const TPKeyAuthorOwnLine;
extern NSString *const TPKeyAuthorJoinNumber;
extern NSString *const TPKeyAuthorDefaultName;
extern NSString *const TPKeyClipboardLinks;
extern NSString *const TPKeyConfirmLike;
extern NSString *const TPKeyHideFollowSuggest;
extern NSString *const TPKeyNoAutoplay;
extern NSString *const TPKeyHideFeedSuggest;
extern NSString *const TPKeyBlockScreenshotDetect;
extern NSString *const TPKeyBlockAnalytics;
extern NSString *const TPKeyExternalBrowser;
extern NSString *const TPKeyHideIGButton;
extern NSString *const TPKeyNoSeen;
extern NSString *const TPKeyKeepUnsent;
extern NSString *const TPKeyNoTyping;
extern NSString *const TPKeyHideProfileSearch;
extern NSString *const TPKeyHideSearchSuggest;
extern NSString *const TPKeyHidePostFeedback;
extern NSString *const TPKeySeenOnReply;
extern NSString *const TPKeyHomeLongPress;
extern NSString *const TPKeyTheme;
extern NSString *const TPKeyLanguage;   // 0 follow system · 1 English · 2 繁體中文 · 3 简体中文 · 4 日本語 · 5 한국어
extern NSString *const TPKeySideloadFix;
extern NSString *const TPKeyCopyProfile;
extern NSString *const TPKeyPinTabBar;
extern NSString *const TPKeyKeepFeed;
extern NSString *const TPKeyNoPullRefresh;
extern NSString *const TPKeyTabNoScrollTop;
extern NSString *const TPKeyTabNoRefresh;

extern NSString *const TPKeyPlaySpeed;
extern NSString *const TPKeyExactTime;
extern NSString *const TPKeyClipboardMode;
extern NSString *const TPKeyBannerPosition;
extern NSString *const TPKeyKeepFeedLimit;

// Posted after setBool:/setInteger:, with userInfo @{ @"key": key }.
extern NSString *const TPPrefsDidChangeNotification;

@interface TPPrefs : NSObject
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key;
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;
+ (void)resetAll;
+ (NSUserDefaults *)defaults;

+ (NSData *)exportJSONData;
+ (NSInteger)importJSONData:(NSData *)data;
@end
