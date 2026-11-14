#import <UIKit/UIKit.h>

UIWindow *TPKeyWindow(void);
UIViewController *TPTopViewController(void);

@interface TPMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) void (^handler)(void);
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler;
@end

extern NSString *const TPThemeDidChangeNotification;

@interface TPUI : NSObject
+ (UIButton *)circleButtonWithSymbol:(NSString *)symbol
                            diameter:(CGFloat)d
                             onTap:(void (^)(void))tap
                         menuItems:(NSArray<TPMenuItem *> *)menuItems;
+ (UIColor *)accent;
+ (UIColor *)accentIcon;
+ (UIColor *)pageColor;
+ (UIColor *)cardColor;
+ (NSInteger)themeCount;
+ (UIColor *)themeColorAtIndex:(NSInteger)i;
+ (NSString *)themeNameAtIndex:(NSInteger)i;
+ (void)hapticLight;
+ (void)hapticSuccess;
+ (void)hapticError;
@end
