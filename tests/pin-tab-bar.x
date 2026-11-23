#import <Foundation/Foundation.h>

static NSString *const TPKeyPinTabBar = @"tp_pin_tab_bar";
static BOOL gPinned;
static NSUInteger gMoveCalls, gFadeCalls;
static double gOffset, gPercent, gAlpha;

@interface TPPrefs : NSObject
+ (BOOL)boolForKey:(NSString *)key;
@end
@implementation TPPrefs
+ (BOOL)boolForKey:(NSString *)key { return [key isEqual:TPKeyPinTabBar] && gPinned; }
@end

@interface _TtC21BCNRootViewController21BCNRootViewController : NSObject
- (void)moveDownTabBarToOffset:(double)offset percentTransitioned:(double)percent;
- (void)setBarButtonAlpha:(double)alpha;
@end
@implementation _TtC21BCNRootViewController21BCNRootViewController
- (void)moveDownTabBarToOffset:(double)offset percentTransitioned:(double)percent {
    gMoveCalls++; gOffset = offset; gPercent = percent;
}
- (void)setBarButtonAlpha:(double)alpha { gFadeCalls++; gAlpha = alpha; }
@end

// PRODUCTION_PIN_HOOK

int main(void) { @autoreleasepool {
    _TtC21BCNRootViewController21BCNRootViewController *root = [_TtC21BCNRootViewController21BCNRootViewController new];
    [root moveDownTabBarToOffset:47.25 percentTransitioned:0.625];
    [root setBarButtonAlpha:0.375];
    NSCAssert(gMoveCalls == 1 && gOffset == 47.25 && gPercent == 0.625, @"Disabled pinning forwards the native doubles unchanged");
    NSCAssert(gFadeCalls == 1 && gAlpha == 0.375, @"Disabled pinning preserves the native fade");
    gPinned = YES;
    [root moveDownTabBarToOffset:81.5 percentTransitioned:1.0];
    [root setBarButtonAlpha:0.0];
    NSCAssert(gMoveCalls == 2 && gOffset == 0.0 && gPercent == 0.0, @"Enabled pinning still calls the native state update with no scrolling displacement");
    NSCAssert(gFadeCalls == 2 && gAlpha == 1.0, @"The scrolling fade cannot leave the pinned buttons invisible");
    gPinned = NO;
    [root moveDownTabBarToOffset:23.75 percentTransitioned:0.25];
    [root setBarButtonAlpha:0.75];
    NSCAssert(gMoveCalls == 3 && gOffset == 23.75 && gPercent == 0.25 && gFadeCalls == 3 && gAlpha == 0.75, @"Switching pinning off immediately restores both native outputs");
    puts("legacy pinned tab Logos hooks: PASS (local stub, no device UI)");
} return 0; }
