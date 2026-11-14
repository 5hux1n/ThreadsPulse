#import <UIKit/UIKit.h>

@interface TPDownloader : NSObject
+ (NSURL *)bestURLFromObject:(id)videoObject;
+ (NSURL *)bestURLFromVideoView:(UIView *)view player:(id)playerHint;
+ (NSString *)debugReportForVideoView:(UIView *)view player:(id)playerHint;
+ (void)showReport:(NSString *)text;

+ (void)downloadItems:(NSArray<NSDictionary *> *)items;
+ (void)downloadVideoURL:(NSURL *)url;

+ (NSURL *)bestVideoURLHarvestedFromObject:(id)obj;
+ (NSURL *)bestImageURLHarvestedFromObject:(id)obj;
+ (NSURL *)bestVideoURLNearView:(UIView *)view;

+ (double)imageAreaFromURL:(NSURL *)url;
+ (void)setPendingReport:(NSString *)report;
+ (void)appendPendingReport:(NSString *)report;
+ (id)safeValue:(id)obj key:(NSString *)key;
+ (id)ivarValue:(id)obj name:(NSString *)name;
+ (void)toast:(NSString *)text;
+ (UIViewController *)topViewController;
@end
