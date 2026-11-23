#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import "TPNotificationPrefs.h"
#import "TPVersion.h"

@interface TPNotificationRecovery : NSObject
@property (copy) NSString *body;
@property (copy) dispatch_block_t resume;
@property (copy) dispatch_block_t fallback;
@property BOOL started;
@property BOOL completed;
@end
@implementation TPNotificationRecovery
@end

static char TPNotificationRecoveryKey;

static NSString *TPUnsentNotificationBody(void) {
    // The extension must not depend on reading resources outside its sandbox.
    NSDictionary<NSString *, NSString *> *bodies = @{
        @"en": @"A message was unsent",
        @"zh-Hans": @"一条消息已被撤回",
        @"zh-Hant": @"一則訊息已被收回",
        @"ja": @"メッセージの送信が取り消されました",
        @"ko": @"메시지 전송이 취소되었습니다",
    };
    NSString *language = [NSBundle preferredLocalizationsFromArray:@[@"en", @"zh-Hans", @"zh-Hant", @"ja", @"ko"]
                                                  forPreferences:NSLocale.preferredLanguages].firstObject;
    return bodies[language] ?: bodies[@"en"];
}

static BOOL TPIsUnsentNotification(NSDictionary *userInfo) {
    id category = userInfo[@"c"];
    return [category isKindOfClass:NSString.class] &&
           [category isEqualToString:@"text_post_app_recall_notif"];
}

static BOOL TPIsUnsentBody(NSString *body) {
    return [body isEqualToString:@"A message was unsent"] ||
           [body isEqualToString:@"A message was unsent."];
}

static UNNotificationContent *TPLocalizeUnsentNotification(UNNotificationContent *content, BOOL isUnsent) {
    if (!content || !(isUnsent || TPIsUnsentNotification(content.userInfo))) return content;
    if (!TPIsUnsentBody(content.body)) return content;
    NSString *localized = TPUnsentNotificationBody();
    if ([localized isEqualToString:@"A message was unsent"]) return content;
    UNMutableNotificationContent *updated = [content mutableCopy];
    updated.body = localized;
    return updated;
}

static void TPCompleteNotification(TPNotificationRecovery *state, id service,
                                   UNNotificationContent *content, BOOL isUnsent,
                                   void (^handler)(UNNotificationContent *)) {
    NSString *body;
    @synchronized (state) {
        if (state.completed) return;
        state.completed = YES;
        body = state.body;
        state.body = nil;
        state.resume = nil;
        state.fallback = nil;
    }
    if (service && objc_getAssociatedObject(service, &TPNotificationRecoveryKey) == state)
        objc_setAssociatedObject(service, &TPNotificationRecoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL restored = content && isUnsent && body.length && TPNotificationPrefsReadKeepUnsent();
    UNNotificationContent *updated;
    if (restored) {
        UNMutableNotificationContent *copy = [content mutableCopy];
        copy.body = body;
        updated = copy;
    } else {
        updated = TPLocalizeUnsentNotification(content, isUnsent);
    }
    NSLog(@"[ThreadsPulseNotifications] completed recall=%d restored=%d translated=%d",
          isUnsent || TPIsUnsentNotification(content.userInfo), restored, !restored && updated != content);
    handler(updated);
}

%group UnsentNotificationLocalization
%hook FBNotificationService
- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent *))handler {
    if (!handler) { %orig; return; }
    BOOL isUnsent = TPIsUnsentNotification(request.content.userInfo);
    TPNotificationRecovery *state = [TPNotificationRecovery new];
    __weak id weakService = self;
    NSLog(@"[ThreadsPulseNotifications] received recall=%d language=%@",
          isUnsent, NSLocale.preferredLanguages.firstObject ?: @"unknown");
    void (^localizedHandler)(UNNotificationContent *) = ^(UNNotificationContent *content) {
        TPCompleteNotification(state, weakService, content, isUnsent, handler);
    };
    id gid = request.content.userInfo[@"gid"];
    if (!isUnsent || ![gid isKindOfClass:NSString.class] || ![gid length] ||
        !TPNotificationPrefsReadKeepUnsent()) {
        %orig(request, localizedHandler);
        return;
    }
    // Native processing deletes gid; read its delivered body before allowing that processing.
    __weak TPNotificationRecovery *weakState = state;
    state.resume = ^{
        TPNotificationRecovery *recovery = weakState;
        id self = weakService;
        if (!recovery || !self) return;
        @synchronized (recovery) {
            if (recovery.started || recovery.completed) return;
            recovery.started = YES;
            recovery.resume = nil;
        }
        void (^nativeHandler)(UNNotificationContent *) = ^(UNNotificationContent *content) {
            TPCompleteNotification(recovery, weakService, content, isUnsent, handler);
        };
        %orig(request, nativeHandler);
    };
    state.fallback = ^{
        TPNotificationRecovery *recovery = weakState;
        if (!recovery) return;
        @synchronized (recovery) {
            recovery.started = YES;
            recovery.resume = nil;
        }
        TPCompleteNotification(recovery, weakService, request.content, isUnsent, handler);
    };
    objc_setAssociatedObject(self, &TPNotificationRecoveryKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
        NSString *body;
        for (UNNotification *notification in notifications) {
            if (![notification.request.identifier isEqualToString:gid]) continue;
            UNNotificationContent *original = notification.request.content;
            if (!TPIsUnsentNotification(original.userInfo) &&
                [original.body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
                body = [original.body copy];
            break;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized (state) {
                if (state.started) return;
                state.body = body;
            }
            dispatch_block_t resume = state.resume;
            if (resume) resume();
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dispatch_block_t resume = state.resume;
        if (resume) resume();
    });
}
- (void)serviceExtensionTimeWillExpire {
    TPNotificationRecovery *state = objc_getAssociatedObject(self, &TPNotificationRecoveryKey);
    dispatch_block_t fallback = state.fallback;
    // Keep our fallback until final completion, including the handoff to native processing.
    if (fallback) { fallback(); return; }
    %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"BarcelonaNotificationExtension"]) return;
        Class service = objc_getClass("FBNotificationService");
        if (!class_getInstanceMethod(service, @selector(didReceiveNotificationRequest:withContentHandler:)) ||
            !class_getInstanceMethod(service, @selector(serviceExtensionTimeWillExpire))) {
            NSLog(@"[ThreadsPulseNotifications] version=%@ hook_ready=0", TP_VERSION);
            return;
        }
        %init(UnsentNotificationLocalization);
        NSLog(@"[ThreadsPulseNotifications] version=%@ hook_ready=1", TP_VERSION);
    }
}
