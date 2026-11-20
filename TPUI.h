#import <UIKit/UIKit.h>

UIWindow *TPKeyWindow(void);
UIViewController *TPTopViewController(void);
// The download button the user last tapped, so follow-up menus can appear next to it.
void TPSetMenuAnchor(UIView *view);
// Protect only visual content; the host keeps its layout, accessibility and touch handling.
void TPSetCaptureProtectedContent(UIView *content, UIView *host);
UIView *TPMenuAnchor(void);

@interface TPMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) void (^handler)(void);
@property (nonatomic, copy) NSString *titleKey;   // localized when shown, so a language change applies
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler;
+ (instancetype)itemWithKey:(NSString *)key symbol:(NSString *)symbol handler:(void (^)(void))handler;
@end

extern NSString *const TPThemeDidChangeNotification;

@interface TPUI : NSObject
+ (UIButton *)circleButtonWithSymbol:(NSString *)symbol
                            diameter:(CGFloat)d
                             onTap:(void (^)(void))tap
                         menuItems:(NSArray<TPMenuItem *> *)menuItems;
// Replaces the long-press menu of a button made by circleButtonWithSymbol.
+ (void)setMenuItems:(NSArray<TPMenuItem *> *)items forButton:(UIButton *)button;
+ (UIColor *)accent;
+ (UIColor *)accentIcon;
// The theme colour's lighter tint, for text on black (e.g. the download pill).
+ (UIColor *)accentOnDark;
+ (UIColor *)pageColor;
+ (UIColor *)cardColor;
+ (NSInteger)themeCount;
+ (UIColor *)themeColorAtIndex:(NSInteger)i;
+ (NSString *)themeNameAtIndex:(NSInteger)i;
+ (void)hapticLight;
+ (void)hapticSuccess;
+ (void)hapticError;
@end
