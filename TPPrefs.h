#import <Foundation/Foundation.h>

extern NSString *const TPKeyBlockAds;
extern NSString *const TPKeyStripTracking;
extern NSString *const TPKeyShowDownloadBtn;
extern NSString *const TPKeyDebugToast;
extern NSString *const TPKeyOriginalAvatar;
extern NSString *const TPKeyOriginalImage;
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
