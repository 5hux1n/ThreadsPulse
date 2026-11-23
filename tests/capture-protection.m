#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// Local ownership/layout stubs only. They cannot verify UIKit screenshot filtering.
typedef NS_OPTIONS(NSUInteger, UIViewAutoresizing) {
    UIViewAutoresizingNone = 0,
    UIViewAutoresizingFlexibleWidth = 1 << 1,
    UIViewAutoresizingFlexibleHeight = 1 << 4,
};

@interface UIColor : NSObject
+ (instancetype)clearColor;
@end
@implementation UIColor
+ (instancetype)clearColor { return [self new]; }
@end

@interface UIView : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic) UIViewAutoresizing autoresizingMask;
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic) BOOL accessibilityElementsHidden;
@property (nonatomic) BOOL isAccessibilityElement;
@property (nonatomic) BOOL clipsToBounds;
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, strong) NSMutableArray<UIView *> *children;
@property (nonatomic, readonly) NSArray<UIView *> *subviews;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index;
- (void)removeFromSuperview;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (void)layoutSubviews;
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view;
@end

@implementation UIView
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super init])) return nil;
    _frame = frame;
    _bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    _children = [NSMutableArray new];
    _userInteractionEnabled = YES;
    return self;
}
- (NSArray<UIView *> *)subviews { return [self.children copy]; }
- (void)setFrame:(CGRect)frame {
    CGSize delta = CGSizeMake(frame.size.width - _frame.size.width, frame.size.height - _frame.size.height);
    _frame = frame;
    _bounds.size = frame.size;
    for (UIView *child in self.subviews) {
        CGRect childFrame = child.frame;
        if (child.autoresizingMask & UIViewAutoresizingFlexibleWidth) childFrame.size.width += delta.width;
        if (child.autoresizingMask & UIViewAutoresizingFlexibleHeight) childFrame.size.height += delta.height;
        child.frame = childFrame;
    }
}
- (void)addSubview:(UIView *)view { [self insertSubview:view atIndex:self.children.count]; }
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index {
    [view removeFromSuperview];
    [self.children insertObject:view atIndex:MIN((NSUInteger)MAX(index, 0), self.children.count)];
    view.superview = self;
}
- (void)removeFromSuperview {
    [self.superview.children removeObjectIdenticalTo:self];
    self.superview = nil;
}
- (void)setNeedsLayout {}
- (void)layoutIfNeeded {
    [self layoutSubviews];
    for (UIView *child in self.subviews) [child layoutIfNeeded];
}
- (void)layoutSubviews {}
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view {
    for (UIView *v = view; v; v = v.superview) {
        rect.origin.x += v.frame.origin.x - v.bounds.origin.x;
        rect.origin.y += v.frame.origin.y - v.bounds.origin.y;
    }
    for (UIView *v = self; v; v = v.superview) {
        rect.origin.x -= v.frame.origin.x - v.bounds.origin.x;
        rect.origin.y -= v.frame.origin.y - v.bounds.origin.y;
    }
    return rect;
}
@end

@interface TPTestCanvasView : UIView @end
@implementation TPTestCanvasView @end

typedef NS_ENUM(NSUInteger, TPTestCanvasMode) {
    TPTestCanvasDirect,
    TPTestCanvasNested,
    TPTestCanvasMissing,
    TPTestCanvasTooDeep,
};
static TPTestCanvasMode sCanvasMode;
static NSUInteger sFieldLayoutsWithNonzeroSize;
static __weak id sLastField;

@interface UITextField : UIView
@property (nonatomic) BOOL secureTextEntry;
@property (nonatomic) BOOL createdNativeViews;
@end
@implementation UITextField
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    sLastField = self;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.secureTextEntry || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
    ++sFieldLayoutsWithNonzeroSize;
    if (self.createdNativeViews) return;
    self.createdNativeViews = YES;
    if (sCanvasMode == TPTestCanvasMissing) return;
    UIView *parent = self;
    NSUInteger wrappers = sCanvasMode == TPTestCanvasNested ? 2 : sCanvasMode == TPTestCanvasTooDeep ? 4 : 0;
    for (NSUInteger i = 0; i < wrappers; ++i) {
        UIView *wrapper = [[UIView alloc] initWithFrame:parent.bounds];
        // Offset wrappers exercise conversion from the secure container's coordinates.
        wrapper.frame = CGRectOffset(wrapper.frame, 3, 5);
        wrapper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [parent addSubview:wrapper];
        parent = wrapper;
    }
    UIView *canvas = [[TPTestCanvasView alloc] initWithFrame:parent.bounds];
    canvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:canvas];
}
@end

static BOOL sCaptureEnabled;
NSString *const TPKeyHideInCaptures = @"tp_hide_in_captures";
NSString *const TPPrefsDidChangeNotification = @"TPPrefsDidChangeNotification";
@interface TPPrefs : NSObject
+ (BOOL)boolForKey:(NSString *)key;
@end
@implementation TPPrefs
+ (BOOL)boolForKey:(NSString *)key { return [key isEqual:TPKeyHideInCaptures] && sCaptureEnabled; }
@end

// INSERT_PRODUCTION_CAPTURE_CODE_HERE

static NSUInteger sAssertions;
#define CHECK(condition, message) do { \
    ++sAssertions; \
    if (!(condition)) { fprintf(stderr, "FAIL: %s (line %d)\n", message, __LINE__); exit(1); } \
} while (0)

static BOOL TPDescendsFrom(UIView *child, UIView *ancestor) {
    for (UIView *view = child; view; view = view.superview) if (view == ancestor) return YES;
    return NO;
}

static UIView *TPTestHost(void) { return [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 36)]; }

static void TPPostCapturePreference(BOOL enabled) {
    sCaptureEnabled = enabled;
    [NSNotificationCenter.defaultCenter postNotificationName:TPPrefsDidChangeNotification
                                                      object:nil userInfo:@{@"key": TPKeyHideInCaptures}];
}

static void TPTestOffAndPreferenceChanges(void) {
    @autoreleasepool {
        sCaptureEnabled = NO;
        sCanvasMode = TPTestCanvasDirect;
        UIView *host = TPTestHost();
        host.isAccessibilityElement = YES;
        UIView *nativeChild = [UIView new];
        [host addSubview:nativeChild];
        UIView *content = [UIView new];
        content.isAccessibilityElement = YES;
        TPSetCaptureProtectedContent(content, host);
        CHECK(content.superview == host, "off keeps content on the host");
        CHECK(CGRectEqualToRect(content.frame, host.bounds), "off content fills the host");
        CHECK(host.userInteractionEnabled, "off does not disable the touch host");
        CHECK(host.isAccessibilityElement && !host.accessibilityElementsHidden,
              "off preserves host accessibility properties");
        CHECK(!content.userInteractionEnabled, "visual content does not intercept touches");
        CHECK(nativeChild.superview == host, "unrelated host child is retained");
        CHECK(!objc_getAssociatedObject(host, kTPButtonSecureKey), "off does not allocate a secure container");

        sCaptureEnabled = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:TPPrefsDidChangeNotification
                                                          object:nil userInfo:@{@"key": @"unrelated"}];
        CHECK(content.superview == host, "unrelated preference does not update capture state");
        TPPostCapturePreference(YES);
        TPCaptureContainer *secure = objc_getAssociatedObject(host, kTPButtonSecureKey);
        CHECK(secure && secure.superview == host, "enabling updates an existing host");
        CHECK(content.superview == secure.canvas, "on places content directly in the secure canvas");
        CHECK(secure.field.secureTextEntry, "the text field remains secure");
        CHECK(secure.field.superview == secure, "the secure field remains in its container");
        CHECK(TPDescendsFrom(secure.canvas, secure.field), "the native secure canvas hierarchy is retained");
        CHECK(secure.field.bounds.size.width > 0 && secure.field.bounds.size.height > 0,
              "the secure field is laid out with nonzero dimensions");
        CHECK(sFieldLayoutsWithNonzeroSize > 0, "secure canvas discovery follows nonzero layout");
        CHECK(CGRectEqualToRect(content.frame, secure.canvas.bounds), "protected content fills its canvas");
        CHECK(host.userInteractionEnabled && !secure.userInteractionEnabled,
              "capture protection preserves the external touch host");
        CHECK(host.isAccessibilityElement && !host.accessibilityElementsHidden,
              "on preserves host accessibility properties");
        CHECK(content.isAccessibilityElement && !secure.accessibilityElementsHidden,
              "protected visual content is not hidden from accessibility");
        CHECK(!secure.field.isAccessibilityElement, "secure text field is not an accessibility element");
        CHECK(nativeChild.superview == host, "enabling preserves unrelated host children");

        host.frame = CGRectMake(0, 0, 60, 52);
        [host layoutIfNeeded];
        CHECK(CGRectEqualToRect(secure.frame, host.bounds), "container follows host resizing");
        CHECK(CGRectEqualToRect(secure.field.frame, secure.bounds), "secure field follows container resizing");
        CHECK(CGRectEqualToRect(content.frame, secure.canvas.bounds), "content follows canvas resizing");

        TPPostCapturePreference(NO);
        CHECK(content.superview == host, "disabling restores existing content to its host");
        CHECK(!secure.superview, "disabling removes the secure container from display");
        CHECK(CGRectEqualToRect(content.frame, host.bounds), "restored content fills the host");
        // Offscreen cached containers cannot inherit a host's autoresizing changes.
        host.frame = CGRectMake(0, 0, 88, 48);
        TPPostCapturePreference(YES);
        CHECK(objc_getAssociatedObject(host, kTPButtonSecureKey) == secure,
              "reenabling reuses the secure owner");
        CHECK(content.superview == secure.canvas, "reenabling protects existing content again");
        CHECK(CGRectEqualToRect(secure.frame, host.bounds), "cached secure container refreshes its size");
        CHECK(CGRectEqualToRect(content.frame, secure.canvas.bounds), "cached canvas content refreshes its size");

        host.userInteractionEnabled = NO;
        TPPostCapturePreference(NO);
        TPPostCapturePreference(YES);
        CHECK(!host.userInteractionEnabled, "protection does not enable a disabled host");
    }
}

static void TPTestReplacementAndNestedCanvas(void) {
    @autoreleasepool {
        sCaptureEnabled = YES;
        sCanvasMode = TPTestCanvasNested;
        UIView *host = TPTestHost();
        UIView *oldContent = [UIView new];
        TPSetCaptureProtectedContent(oldContent, host);
        TPCaptureContainer *secure = objc_getAssociatedObject(host, kTPButtonSecureKey);
        CHECK(secure != nil, "nested canvas is found");
        CHECK(secure.canvas.superview != secure.field, "test uses a nested native canvas");
        CHECK(TPDescendsFrom(secure.canvas, secure.field), "nested canvas stays under its secure field");
        CHECK(CGRectEqualToRect([secure convertRect:secure.canvas.bounds fromView:secure.canvas], secure.bounds),
              "nested canvas covers the secure container in converted coordinates");
        UIView *newContent = [UIView new];
        TPSetCaptureProtectedContent(newContent, host);
        CHECK(!oldContent.superview, "replacing content removes the old content");
        CHECK(newContent.superview == secure.canvas, "replacement is protected immediately");
        CHECK(objc_getAssociatedObject(host, kTPButtonContentKey) == newContent,
              "host tracks only the replacement content");
        TPPostCapturePreference(NO);
        CHECK(newContent.superview == host && !oldContent.superview,
              "preference changes affect the replacement, not the removed content");
    }
}

static void TPTestMissingCanvasFallback(void) {
    @autoreleasepool {
        sCaptureEnabled = YES;
        sCanvasMode = TPTestCanvasMissing;
        UIView *host = TPTestHost();
        UIView *content = [UIView new];
        TPSetCaptureProtectedContent(content, host);
        CHECK(content.superview == host, "missing canvas falls back to visible content");
        CHECK(CGRectEqualToRect(content.frame, host.bounds), "fallback content fills host bounds");
        CHECK(!objc_getAssociatedObject(host, kTPButtonSecureKey), "failed container is not retained");
        CHECK(host.userInteractionEnabled, "fallback preserves the touch host");
        sCanvasMode = TPTestCanvasDirect;
        TPPostCapturePreference(YES);
        TPCaptureContainer *secure = objc_getAssociatedObject(host, kTPButtonSecureKey);
        CHECK(secure && content.superview == secure.canvas, "a later update can recover from fallback");
    }
    @autoreleasepool {
        sCaptureEnabled = YES;
        sCanvasMode = TPTestCanvasTooDeep;
        UIView *host = TPTestHost();
        UIView *content = [UIView new];
        TPSetCaptureProtectedContent(content, host);
        CHECK(content.superview == host, "canvas search depth is bounded and falls back safely");
    }
}

static void TPTestOwnerRelease(void) {
    __weak UIView *weakHost;
    __weak UIView *weakContent;
    __weak TPCaptureContainer *weakContainer;
    __weak UITextField *weakField;
    @autoreleasepool {
        sCaptureEnabled = YES;
        sCanvasMode = TPTestCanvasDirect;
        UIView *host = TPTestHost();
        UIView *content = [UIView new];
        TPSetCaptureProtectedContent(content, host);
        TPCaptureContainer *secure = objc_getAssociatedObject(host, kTPButtonSecureKey);
        weakHost = host;
        weakContent = content;
        weakContainer = secure;
        weakField = secure.field;
        CHECK(weakField == sLastField, "secure field is retained while host is alive");
    }
    CHECK(!weakHost, "preference tracking does not retain released hosts");
    CHECK(!weakContent && !weakContainer && !weakField, "secure hierarchy is released with its owner");
    TPPostCapturePreference(NO);
}

int main(void) {
    @autoreleasepool {
        TPTestOffAndPreferenceChanges();
        TPTestReplacementAndNestedCanvas();
        TPTestMissingCanvasFallback();
        TPTestOwnerRelease();
        printf("PASS: capture protection ownership/layout (%lu checks; local UIKit stubs, no screenshot/device validation)\n",
               (unsigned long)sAssertions);
    }
    return 0;
}
