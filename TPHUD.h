#import <UIKit/UIKit.h>

@interface TPHUD : NSObject
+ (instancetype)showWithTitle:(NSString *)title cancel:(void (^)(void))cancel;
- (void)setTitle:(NSString *)title;
- (void)setProgress:(CGFloat)progress subtitle:(NSString *)subtitle;
- (void)finishSuccess:(NSString *)message;
- (void)finishFailure:(NSString *)message;
- (void)dismiss;

+ (void)toast:(NSString *)text;
+ (void)bannerWithText:(NSString *)text symbol:(NSString *)symbol action:(NSString *)actionTitle handler:(void (^)(void))handler;
+ (void)bannerWithText:(NSString *)text symbol:(NSString *)symbol action:(NSString *)actionTitle
              position:(NSInteger)position handler:(void (^)(void))handler;
@end
