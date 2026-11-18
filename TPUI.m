#import "TPUI.h"
#import <objc/runtime.h>
#import "TPPrefs.h"
#import "TPLocalization.h"
#import "TPHUD.h"

UIWindow *TPKeyWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
            if (!fallback && !w.isHidden) fallback = w;
        }
    }
    return fallback;
}

UIViewController *TPTopViewController(void) {
    UIViewController *vc = TPKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

@implementation TPMenuItem
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler {
    TPMenuItem *i = [TPMenuItem new];
    i.title = title; i.symbol = symbol; i.handler = handler;
    return i;
}
+ (instancetype)itemWithKey:(NSString *)key symbol:(NSString *)symbol handler:(void (^)(void))handler {
    TPMenuItem *i = [self itemWithTitle:key symbol:symbol handler:handler];
    i.titleKey = key;
    return i;
}
- (NSString *)title { return _titleKey ? TPL(_titleKey) : _title; }
@end

// Long-press state of a circle button. Done with the button's own touch tracking rather than a
// gesture recognizer: on full-screen video pages Threads' gestures kept the recognizer from ever
// receiving the touch, while the button itself still got it.
@interface TPUI (TPHoldMenu)
+ (void)tp_showMenu:(NSArray<TPMenuItem *> *)items from:(UIView *)src;
@end

@interface TPHoldState : NSObject
@property (nonatomic, copy) NSArray<TPMenuItem *> *items;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL fired;
@property (nonatomic) NSTimeInterval shownAt;
- (BOOL)recentlyShown;
@end
// Long-press menu, opened by whichever of two paths sees the hold first:
// - a long-press gesture on the button: gets the touch the moment the finger lands (in the feed,
//   Threads' own gestures hold the touch back from the button itself for ~0.8 s);
// - the button's own touch tracking: the only one that works on full-screen video pages, where
//   the gesture never receives the touch.
@implementation TPHoldState
- (BOOL)recentlyShown { return NSProcessInfo.processInfo.systemUptime - self.shownAt < 1.2; }
- (void)show:(UIButton *)b via:(NSString *)path {
    if (!b || !self.items.count || [self recentlyShown]) return;
    self.fired = YES;
    self.shownAt = NSProcessInfo.processInfo.systemUptime;
    [self.timer invalidate];
    self.timer = nil;
    [TPUI tp_showMenu:self.items from:b];
}
- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) [self show:(UIButton *)g.view via:@"gesture"];
}
- (void)touchDown:(UIButton *)b event:(UIEvent *)event {
    [self.timer invalidate];
    self.timer = nil;
    if ([self recentlyShown]) { self.fired = YES; return; }   // the gesture already opened it
    self.fired = NO;
    if (!self.items.count) return;
    __weak TPHoldState *ws = self;
    __weak UIButton *wb = b;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.45 repeats:NO block:^(NSTimer *x) {
        UIButton *bb = wb;
        if (bb.isTracking) [ws show:bb via:@"touch"];
    }];
}
@end
static const void *kTPHoldKey = &kTPHoldKey;

NSString *const TPThemeDidChangeNotification = @"TPThemeDidChangeNotification";

// A view whose contents iOS leaves out of screenshots and screen recordings, taken from a
// secure UITextField (the same mechanism that hides typed passwords). Returns nil if the
// private canvas view isn't there on this iOS version, in which case buttons draw normally.
UIView *TPCaptureProtectedView(void) {
    UITextField *field = [UITextField new];
    field.secureTextEntry = YES;
    UIView *canvas = nil;
    for (UIView *v in field.subviews)
        if ([NSStringFromClass([v class]) containsString:@"CanvasView"]) { canvas = v; break; }
    if (!canvas) return nil;
    for (UIView *v in canvas.subviews) [v removeFromSuperview];
    [canvas removeFromSuperview];
    canvas.userInteractionEnabled = NO;
    canvas.backgroundColor = UIColor.clearColor;
    return canvas;
}

static const void *kTPButtonContentKey = &kTPButtonContentKey;
static const void *kTPButtonSecureKey  = &kTPButtonSecureKey;

// Puts the button's content inside or outside the capture-protected layer, per the setting.
static void TPApplyCaptureProtection(UIButton *b) {
    UIView *content = objc_getAssociatedObject(b, kTPButtonContentKey);
    if (!content) return;
    UIView *secure = objc_getAssociatedObject(b, kTPButtonSecureKey);
    if ([TPPrefs boolForKey:TPKeyHideInCaptures]) {
        if (!secure) {
            secure = TPCaptureProtectedView();
            if (!secure) { if (content.superview != b) [b insertSubview:content atIndex:0]; return; }
            secure.frame = b.bounds;
            secure.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            secure.clipsToBounds = NO;
            objc_setAssociatedObject(b, kTPButtonSecureKey, secure, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        content.frame = secure.bounds;
        [secure addSubview:content];
        if (secure.superview != b) [b insertSubview:secure atIndex:0];
    } else {
        [secure removeFromSuperview];
        content.frame = b.bounds;
        if (content.superview != b) [b insertSubview:content atIndex:0];
    }
}

// Live buttons, so a change to the setting applies to the ones already on screen.
static NSHashTable<UIButton *> *sTPButtons;
static void TPTrackButton(UIButton *b) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sTPButtons = [NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:TPPrefsDidChangeNotification object:nil
                                                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (![n.userInfo[@"key"] isEqual:TPKeyHideInCaptures]) return;
            for (UIButton *x in sTPButtons.allObjects) TPApplyCaptureProtection(x);
        }];
    });
    [sTPButtons addObject:b];
}

static __weak UIView *sTPMenuAnchor;
void TPSetMenuAnchor(UIView *view) { sTPMenuAnchor = view; }
UIView *TPMenuAnchor(void) { UIView *v = sTPMenuAnchor; return v.window ? v : nil; }

@implementation TPUI

typedef struct { uint32_t main, iconDark, iconLight; const char *name; } TPTheme;
static const TPTheme kTPThemes[] = {
    { 0xD85A30, 0xF0997B, 0xC44F28, "Coral" },
    { 0x2F7BEA, 0x7FB2FF, 0x1F63C9, "Ocean" },
    { 0x1FA971, 0x6FD9A8, 0x168A5B, "Mint" },
    { 0x8A5CF5, 0xB9A0FF, 0x7046D9, "Lavender" },
    { 0xE0457B, 0xFF95B8, 0xC2335F, "Sakura" },
    { 0xE08A00, 0xFFC15A, 0xB86F00, "Amber" },
};
static UIColor *TPHex(uint32_t v) {
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}
static const TPTheme *TPCurrentTheme(void) {
    NSInteger i = [TPPrefs integerForKey:TPKeyTheme];
    if (i < 0 || i >= (NSInteger)(sizeof(kTPThemes) / sizeof(kTPThemes[0]))) i = 0;
    return &kTPThemes[i];
}
+ (NSInteger)themeCount { return sizeof(kTPThemes) / sizeof(kTPThemes[0]); }
+ (UIColor *)themeColorAtIndex:(NSInteger)i { return TPHex(kTPThemes[MAX(0, MIN(i, [self themeCount] - 1))].main); }
+ (NSString *)themeNameAtIndex:(NSInteger)i { return @(kTPThemes[MAX(0, MIN(i, [self themeCount] - 1))].name); }
+ (UIColor *)accent { return TPHex(TPCurrentTheme()->main); }
+ (UIColor *)accentOnDark { return TPHex(TPCurrentTheme()->iconDark); }

+ (UIColor *)accentIcon {
    const TPTheme *t = TPCurrentTheme();
    UIColor *dark = TPHex(t->iconDark), *light = TPHex(t->iconLight);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

static UIColor *TPDynamic(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}
+ (UIColor *)pageColor { return TPDynamic([UIColor colorWithWhite:0.96 alpha:1], [UIColor colorWithWhite:0.063 alpha:1]); }
+ (UIColor *)cardColor { return TPDynamic([UIColor colorWithWhite:1 alpha:0.85], [UIColor colorWithWhite:1 alpha:0.08]); }

+ (void)hapticLight {
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}
+ (void)hapticSuccess {
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeSuccess];
}
+ (void)hapticError {
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeError];
}

+ (UIButton *)circleButtonWithSymbol:(NSString *)symbol
                            diameter:(CGFloat)d
                             onTap:(void (^)(void))tap
                         menuItems:(NSArray<TPMenuItem *> *)menuItems {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, d, d);
    b.layer.cornerRadius = d / 2;
    b.layer.borderWidth = 0.5;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.18;
    b.layer.shadowRadius = 8;
    b.layer.shadowOffset = CGSizeMake(0, 2);

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = b.bounds;
    blur.userInteractionEnabled = NO;
    blur.layer.cornerRadius = d / 2;
    blur.clipsToBounds = YES;
    UIView *frost = [[UIView alloc] initWithFrame:blur.bounds];
    frost.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    frost.userInteractionEnabled = NO;
    [blur.contentView addSubview:frost];
    [b insertSubview:blur atIndex:0];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:d * 0.40 weight:UIImageSymbolWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@"arrow.down" withConfiguration:cfg];
    UIImageView *icon = [[UIImageView alloc] initWithFrame:b.bounds];
    icon.contentMode = UIViewContentModeCenter;
    icon.userInteractionEnabled = NO;
    if (img) {
        icon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        icon.tintColor = UIColor.whiteColor;
    } else {
        UILabel *l = [[UILabel alloc] initWithFrame:b.bounds];
        l.text = @"↓";
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:d * 0.5 weight:UIFontWeightBold];
        l.textAlignment = NSTextAlignmentCenter;
        [icon addSubview:l];
    }
    [b addSubview:icon];

    // Everything visible (frost, icon, ring, shadow) lives in one content view, so it can be moved
    // in and out of a capture-protected layer whenever "Hide Buttons in Screenshots" changes.
    UIView *content = [[UIView alloc] initWithFrame:b.bounds];
    content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.userInteractionEnabled = NO;
    content.layer.cornerRadius = d / 2;
    content.layer.borderWidth = b.layer.borderWidth;
    content.layer.borderColor = b.layer.borderColor;
    content.layer.shadowColor = b.layer.shadowColor;
    content.layer.shadowOpacity = b.layer.shadowOpacity;
    content.layer.shadowRadius = b.layer.shadowRadius;
    content.layer.shadowOffset = b.layer.shadowOffset;
    b.layer.borderWidth = 0;
    b.layer.shadowOpacity = 0;
    [blur removeFromSuperview];
    [icon removeFromSuperview];
    [content addSubview:blur];
    [content addSubview:icon];
    objc_setAssociatedObject(b, kTPButtonContentKey, content, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TPApplyCaptureProtection(b);
    TPTrackButton(b);
    b.accessibilityLabel = TPL(@"Download");

    __weak UIButton *wb = b;
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [UIView animateWithDuration:0.12 animations:^{ wb.transform = CGAffineTransformMakeScale(0.88, 0.88); }];
    }] forControlEvents:UIControlEventTouchDown];
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:6
                            options:0 animations:^{ wb.transform = CGAffineTransformIdentity; } completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    TPHoldState *hold = [TPHoldState new];
    hold.items = menuItems;
    objc_setAssociatedObject(b, kTPHoldKey, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak TPHoldState *wh = hold;
    [b addTarget:hold action:@selector(touchDown:event:) forControlEvents:UIControlEventTouchDown];
    if (menuItems.count) {
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:hold action:@selector(longPressed:)];
        lp.minimumPressDuration = 0.45;
        [b addGestureRecognizer:lp];
    }
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [wh.timer invalidate]; wh.timer = nil; }]
     forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    if (tap) {
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) {
            if (wh.fired || [wh recentlyShown]) { wh.fired = NO; return; }   // the hold already opened the menu
            [TPUI hapticLight]; TPSetMenuAnchor(wb); tap();
        }] forControlEvents:UIControlEventTouchUpInside];
    }
    return b;
}

+ (void)setMenuItems:(NSArray<TPMenuItem *> *)items forButton:(UIButton *)button {
    TPHoldState *h = objc_getAssociatedObject(button, kTPHoldKey);
    h.items = items;
}

+ (void)tp_showMenu:(NSArray<TPMenuItem *> *)items from:(UIView *)src {
    src.transform = CGAffineTransformIdentity;
    [TPUI hapticLight];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (TPMenuItem *item in items) {
        void (^h)(void) = item.handler;
        __weak UIView *wsrc = src;
        UIAlertAction *a = [UIAlertAction actionWithTitle:item.title style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *x) { TPSetMenuAnchor(wsrc); if (h) h(); }];
        UIImage *img = item.symbol ? [UIImage systemImageNamed:item.symbol] : nil;
        if (img) { @try { [a setValue:img forKey:@"image"]; } @catch (__unused id e) {} }
        [sheet addAction:a];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:TPL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = src;
    sheet.popoverPresentationController.sourceRect = src.bounds;
    // Normally the app's top controller; if it can't present right now, the screen the button is on.
    UIViewController *from = TPTopViewController();
    if (!from.view.window || from.isBeingDismissed || from.isBeingPresented) {
        for (UIResponder *r = src; r; r = r.nextResponder)
            if ([r isKindOfClass:[UIViewController class]]) { from = (UIViewController *)r; break; }
        while (from.presentedViewController && !from.presentedViewController.isBeingDismissed) from = from.presentedViewController;
    }
    [from presentViewController:sheet animated:YES completion:nil];
}
@end
