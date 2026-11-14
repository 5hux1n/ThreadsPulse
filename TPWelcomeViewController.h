#import <UIKit/UIKit.h>

/// 全螢幕歡迎畫面：告訴使用者怎麼打開插件設定。
@interface TPWelcomeViewController : UIViewController
+ (void)presentIfNeeded;
+ (void)present;
@end
