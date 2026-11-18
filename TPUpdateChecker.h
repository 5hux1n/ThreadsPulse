#import <UIKit/UIKit.h>

// Checks GitHub Releases for a newer ThreadsPulse and offers to open its page.
@interface TPUpdateChecker : NSObject
+ (void)checkAutomatically;   // at most once a day, when the setting is on; skips a skipped version
+ (void)checkNow;             // from the About page: always checks and always reports the result
@end
