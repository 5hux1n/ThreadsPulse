#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@class UNMutableNotificationContent;
@interface UNNotificationContent : NSObject <NSMutableCopying>
@property (copy) NSString *body, *title, *subtitle, *threadIdentifier, *categoryIdentifier;
@property (copy) NSDictionary *userInfo;
@property (copy) NSArray *attachments;
@property (strong) id sound;
@end
@interface UNMutableNotificationContent : UNNotificationContent
@end
@implementation UNNotificationContent
- (id)mutableCopyWithZone:(NSZone *)zone {
    UNMutableNotificationContent *copy = [UNMutableNotificationContent new];
    copy.body = self.body; copy.title = self.title; copy.subtitle = self.subtitle;
    copy.threadIdentifier = self.threadIdentifier; copy.categoryIdentifier = self.categoryIdentifier;
    copy.userInfo = self.userInfo; copy.attachments = self.attachments; copy.sound = self.sound;
    return copy;
}
@end
@implementation UNMutableNotificationContent
@end

@interface UNNotificationRequest : NSObject
@property (copy) NSString *identifier;
@property (strong) UNNotificationContent *content;
@property (strong) id trigger;
@end
@implementation UNNotificationRequest
@end

@interface UNNotification : NSObject
@property (strong) UNNotificationRequest *request;
@end
@implementation UNNotification
@end

static BOOL gKeepUnsent, gQueryDefer, gQueryBackground;
static NSUInteger gQueryCalls;
static NSArray<UNNotification *> *gDelivered;
static void (^gQueryPending)(NSArray<UNNotification *> *);

BOOL TPNotificationPrefsReadKeepUnsent(void) { return gKeepUnsent; }

@interface UNUserNotificationCenter : NSObject
+ (instancetype)currentNotificationCenter;
- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *))completion;
@end
@implementation UNUserNotificationCenter
+ (instancetype)currentNotificationCenter {
    static UNUserNotificationCenter *center;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ center = [self new]; });
    return center;
}
- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *))completion {
    gQueryCalls++;
    if (gQueryDefer) gQueryPending = [completion copy];
    else if (gQueryBackground) {
        NSArray *notifications = gDelivered ?: @[];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ completion(notifications); });
    } else completion(gDelivered ?: @[]);
}
@end

static NSUInteger gOriginalCalls;
static NSUInteger gExpiryCalls;
static BOOL gDefer, gUseForwardedContent, gNilHandlerForwarded, gTranslates, gDuplicateNativeCallback, gLastNativeWasMain;
static BOOL gExpireAtNativeEntry;
static UNNotificationContent *gNativeResult;
static UNNotificationRequest *gReceivedRequest;
static NSString *gTranslation;
static void (^gPending)(UNNotificationContent *);

@interface FBNotificationService : NSObject
- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent *))handler;
- (void)serviceExtensionTimeWillExpire;
@end
@implementation FBNotificationService
- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent *))handler {
    gOriginalCalls++; gReceivedRequest = request; gLastNativeWasMain = NSThread.isMainThread;
    if (!handler) { gNilHandlerForwarded = YES; return; }
    if (gExpireAtNativeEntry) [self serviceExtensionTimeWillExpire];
    if (gDefer) gPending = [handler copy];
    else {
        handler(gUseForwardedContent ? request.content : gNativeResult);
        if (gDuplicateNativeCallback) handler(gUseForwardedContent ? request.content : gNativeResult);
    }
}
- (void)serviceExtensionTimeWillExpire {
    gExpiryCalls++;
    void (^pending)(UNNotificationContent *) = gPending;
    gPending = nil;
    if (pending) pending(gNativeResult);
}
@end

// PRODUCTION_NOTIFICATION_HOOK

static UNNotificationContent *Content(NSString *body, id marker) {
    UNNotificationContent *content = [UNNotificationContent new];
    content.body = body; content.userInfo = marker ? @{@"c": marker, @"message_id": @"opaque-id"} : @{};
    content.title = @"Sender"; content.subtitle = @"Subtitle";
    content.threadIdentifier = @"thread-123"; content.categoryIdentifier = @"message-category";
    content.attachments = @[[NSObject new]]; content.sound = [NSObject new];
    return content;
}

static UNNotificationRequest *Request(UNNotificationContent *content) {
    UNNotificationRequest *request = [UNNotificationRequest new];
    request.identifier = @"opaque-notification-id"; request.content = content; request.trigger = [NSObject new];
    return request;
}

static void CheckMetadata(UNNotificationContent *result, UNNotificationContent *original) {
    NSCAssert([result.title isEqual:original.title] && [result.subtitle isEqual:original.subtitle] &&
              [result.userInfo isEqual:original.userInfo] && [result.threadIdentifier isEqual:original.threadIdentifier] &&
              [result.categoryIdentifier isEqual:original.categoryIdentifier] &&
              [result.attachments isEqual:original.attachments] && result.sound == original.sound,
              @"Preserve all mutableCopy notification metadata");
}

static void CheckRequest(UNNotificationRequest *original) {
    if (!original) { NSCAssert(!gReceivedRequest, @"Nil requests pass through unchanged"); return; }
    NSCAssert(gReceivedRequest == original && gReceivedRequest.content == original.content &&
              [gReceivedRequest.identifier isEqual:original.identifier] && gReceivedRequest.trigger == original.trigger,
              @"Preserve the original request, content, identifier and trigger");
}

static UNNotificationContent *DeliverRequest(FBNotificationService *service, UNNotificationRequest *request,
                                             UNNotificationContent *final) {
    gNativeResult = final;
    __block NSUInteger calls = 0; __block UNNotificationContent *result;
    NSUInteger originalsBefore = gOriginalCalls;
    [service didReceiveNotificationRequest:request withContentHandler:^(UNNotificationContent *content) { calls++; result = content; }];
    NSCAssert(calls == 1 && gOriginalCalls == originalsBefore + 1, @"Call the native service and final handler once");
    CheckRequest(request);
    return result;
}

static UNNotificationContent *Deliver(FBNotificationService *service, UNNotificationContent *original,
                                      UNNotificationContent *final) {
    return DeliverRequest(service, Request(original), final);
}

@interface TPTestDelivery : NSObject
@property NSUInteger calls;
@property (strong) UNNotificationContent *result;
@end
@implementation TPTestDelivery
@end

static void Pump(NSTimeInterval seconds) {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void WaitFor(BOOL (^condition)(void), NSString *reason) {
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 2;
    while (!condition()) {
        NSCAssert(NSProcessInfo.processInfo.systemUptime < deadline, @"Timed out: %@", reason);
        Pump(0.002);
    }
}

static void ResetRecovery(void) {
    gKeepUnsent = YES; gQueryDefer = NO; gQueryBackground = NO;
    gDefer = NO; gUseForwardedContent = NO; gDuplicateNativeCallback = NO;
    gExpireAtNativeEntry = NO;
    gOriginalCalls = 0; gQueryCalls = 0; gExpiryCalls = 0;
    gReceivedRequest = nil; gPending = nil; gQueryPending = nil; gDelivered = @[];
}

static UNNotificationRequest *RecallRequest(id gid) {
    UNNotificationContent *content = Content(@"A message was unsent", @"text_post_app_recall_notif");
    NSMutableDictionary *info = [content.userInfo mutableCopy];
    if (gid) info[@"gid"] = gid;
    content.userInfo = info;
    return Request(content);
}

static UNNotification *Delivered(NSString *identifier, NSString *body, id marker) {
    UNNotification *notification = [UNNotification new];
    notification.request = Request(Content(body, marker));
    notification.request.identifier = identifier;
    return notification;
}

static TPTestDelivery *Begin(FBNotificationService *service, UNNotificationRequest *request,
                             UNNotificationContent *final) {
    gNativeResult = final;
    TPTestDelivery *delivery = [TPTestDelivery new];
    [service didReceiveNotificationRequest:request withContentHandler:^(UNNotificationContent *content) {
        @synchronized (delivery) { delivery.calls++; delivery.result = content; }
    }];
    return delivery;
}

static void CheckFallback(UNNotificationContent *result, UNNotificationContent *final) {
    NSCAssert(gTranslates ? result != final && [result.body isEqual:gTranslation] : result == final,
              @"An unavailable original body follows the exact built-in language fallback");
    CheckMetadata(result, final);
}

static void CompleteQuery(NSArray<UNNotification *> *notifications) {
    void (^pending)(NSArray<UNNotification *> *) = gQueryPending;
    gQueryPending = nil;
    NSCAssert(pending, @"A delivery lookup is pending");
    pending(notifications);
}

static void RunRecoveryTests(FBNotificationService *service) {
    NSString *gid = @"exact-original-id";
    NSString *marker = @"text_post_app_recall_notif";
    UNNotificationContent *final = Content(@"A message was unsent.", nil);
    final.title = @"Native final title"; final.subtitle = @"Native final subtitle";
    final.threadIdentifier = @"native-final-thread"; final.categoryIdentifier = @"native-final-category";
    final.userInfo = @{@"native_metadata": @YES};

    for (id invalid in @[@"", @42, NSNull.null, @[]]) {
        ResetRecovery();
        UNNotificationRequest *request = RecallRequest(invalid);
        TPTestDelivery *delivery = Begin(service, request, final);
        NSCAssert(gQueryCalls == 0 && gOriginalCalls == 1 && delivery.calls == 1,
                  @"Empty or non-string gid must never query delivered notifications");
        CheckFallback(delivery.result, final); CheckRequest(request);
    }
    ResetRecovery();
    TPTestDelivery *delivery = Begin(service, RecallRequest(nil), final);
    NSCAssert(gQueryCalls == 0 && gOriginalCalls == 1 && delivery.calls == 1, @"Missing gid is ineligible");
    for (id category in @[@"ordinary", @"text_post_app_recall_notif_extra", @1, NSNull.null]) {
        ResetRecovery();
        UNNotificationRequest *request = RecallRequest(gid);
        request.content.userInfo = @{@"c": category, @"gid": gid};
        UNNotificationContent *ordinaryFinal = Content(@"A message was unsent", nil);
        delivery = Begin(service, request, ordinaryFinal);
        NSCAssert(gQueryCalls == 0 && gOriginalCalls == 1 && delivery.result == ordinaryFinal,
                  @"Only the exact recall category may recover or translate an unmarked final body");
    }
    ResetRecovery(); gKeepUnsent = NO;
    delivery = Begin(service, RecallRequest(gid), final);
    NSCAssert(gQueryCalls == 0 && gOriginalCalls == 1 && delivery.calls == 1,
              @"Disabled keep-unsent skips recovery without disabling localization");
    CheckFallback(delivery.result, final);

    // A candidate sharing the thread, message_id or n field is not an identifier match.
    ResetRecovery();
    UNNotification *wrong = Delivered(@"other-request-id", @"Wrong original", nil);
    wrong.request.content.userInfo = @{@"n": gid, @"message_id": gid};
    gDelivered = @[wrong];
    delivery = Begin(service, RecallRequest(gid), final);
    WaitFor(^BOOL { return delivery.calls == 1; }, @"reject a near-match identifier");
    NSCAssert(gQueryCalls == 1 && gOriginalCalls == 1, @"Query once and continue native once for a wrong gid");
    CheckFallback(delivery.result, final);

    for (id rejectedBody in @[NSNull.null, @"", @" \n\t", @"Recall body"]) {
        ResetRecovery();
        BOOL recallCandidate = [rejectedBody isEqual:@"Recall body"];
        gDelivered = @[Delivered(gid, rejectedBody == NSNull.null ? nil : rejectedBody,
                                recallCandidate ? marker : nil)];
        delivery = Begin(service, RecallRequest(gid), final);
        WaitFor(^BOOL { return delivery.calls == 1; }, @"reject blank or recall candidates");
        CheckFallback(delivery.result, final);
    }

    for (NSString *originalBody in @[@"Original private message", @"A message was unsent", @"A message was unsent."]) {
        for (NSString *nativeBody in @[@"A message was unsent", @"一条消息已被撤回"]) {
            ResetRecovery(); gQueryBackground = YES;
            gDelivered = @[wrong, Delivered(gid, originalBody, nil)];
            UNNotificationRequest *request = RecallRequest(gid);
            UNNotificationContent *nativeFinal = [final mutableCopy]; nativeFinal.body = nativeBody;
            delivery = Begin(service, request, nativeFinal);
            NSCAssert(gOriginalCalls == 0 && delivery.calls == 0, @"Query finishes before native deletion starts");
            WaitFor(^BOOL { return delivery.calls == 1; }, @"recover the exact original notification body");
            NSCAssert(gOriginalCalls == 1 && gQueryCalls == 1 && gLastNativeWasMain &&
                      delivery.result != nativeFinal && [delivery.result.body isEqual:originalBody],
                      @"Resume native on main and restore English or localized recall text without retranslating original messages");
            CheckMetadata(delivery.result, nativeFinal); CheckRequest(request);
            NSCAssert([nativeFinal.body isEqual:nativeBody] && [request.content.body isEqual:@"A message was unsent"],
                      @"Restoration does not mutate either native content object");
        }
    }

    ResetRecovery(); gDelivered = @[Delivered(gid, @"Original body", nil)];
    delivery = Begin(service, RecallRequest(gid), nil);
    WaitFor(^BOOL { return delivery.calls == 1; }, @"nil native result with recoverable body");
    NSCAssert(delivery.result == nil && gOriginalCalls == 1, @"Preserve nil native final content even with a matching original");

    ResetRecovery(); gQueryDefer = YES;
    delivery = Begin(service, RecallRequest(gid), final);
    gKeepUnsent = NO; CompleteQuery(@[Delivered(gid, @"Original body", nil)]);
    WaitFor(^BOOL { return delivery.calls == 1; }, @"disable recovery while the query is pending");
    CheckFallback(delivery.result, final);

    ResetRecovery(); gDefer = YES; gDelivered = @[Delivered(gid, @"Original body", nil)];
    delivery = Begin(service, RecallRequest(gid), final);
    WaitFor(^BOOL { return gOriginalCalls == 1; }, @"wait for a deferred native result");
    NSCAssert(delivery.calls == 0 && gPending, @"Do not preempt native asynchronous processing");
    gKeepUnsent = NO;
    void (^nativePending)(UNNotificationContent *) = gPending; gPending = nil;
    nativePending(final); nativePending(final);
    NSCAssert(delivery.calls == 1, @"A duplicate native callback still reaches the app exactly once");
    CheckFallback(delivery.result, final);

    ResetRecovery(); gDuplicateNativeCallback = YES; gDelivered = @[Delivered(gid, @"Original body", nil)];
    delivery = Begin(service, RecallRequest(gid), final);
    WaitFor(^BOOL { return delivery.calls == 1; }, @"duplicate synchronous native callbacks");
    NSCAssert(gOriginalCalls == 1 && [delivery.result.body isEqual:@"Original body"],
              @"A recovered notification has exactly one native entry and one final result");

    ResetRecovery(); gQueryDefer = YES;
    NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
    delivery = Begin(service, RecallRequest(gid), final);
    WaitFor(^BOOL { return delivery.calls == 1; }, @"a delivered-notification query that never responds");
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - began;
    NSCAssert(elapsed >= 0.25 && elapsed < 1.5 && gOriginalCalls == 1,
              @"The approximately 0.35-second deadline releases native without an indefinite wait (%f)", elapsed);
    CheckFallback(delivery.result, final);
    CompleteQuery(@[Delivered(gid, @"Late original body", nil)]); Pump(0.02);
    NSCAssert(gOriginalCalls == 1 && delivery.calls == 1, @"A late query cannot restart native or redeliver the handler");
    CheckFallback(delivery.result, final);

    ResetRecovery(); gQueryDefer = YES; gDefer = YES;
    delivery = Begin(service, RecallRequest(gid), final);
    WaitFor(^BOOL { return gOriginalCalls == 1; }, @"deadline starts native while its result remains pending");
    CompleteQuery(@[Delivered(gid, @"Too-late body", nil)]); Pump(0.01);
    nativePending = gPending; gPending = nil; nativePending(final);
    NSCAssert(delivery.calls == 1 && gOriginalCalls == 1, @"A late query does not alter an already-started native delivery");
    CheckFallback(delivery.result, final);

    ResetRecovery(); gQueryDefer = YES;
    UNNotificationRequest *request = RecallRequest(gid);
    delivery = Begin(service, request, final);
    dispatch_semaphore_t expired = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [service serviceExtensionTimeWillExpire]; dispatch_semaphore_signal(expired);
    });
    NSCAssert(dispatch_semaphore_wait(expired, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
              @"Pending expiry finishes immediately on Apple's separate expiry thread without needing main-queue progress");
    NSCAssert(gOriginalCalls == 0 && gExpiryCalls == 0 && delivery.calls == 1,
              @"Pending expiry finishes the saved handler without starting native after expiry");
    CheckFallback(delivery.result, request.content);
    CompleteQuery(@[Delivered(gid, @"Late expired body", nil)]); Pump(0.38);
    NSCAssert(gOriginalCalls == 0 && gExpiryCalls == 0 && delivery.calls == 1,
              @"Neither query nor deadline may restart an expired pending delivery");

    ResetRecovery(); gDefer = YES; gDelivered = @[Delivered(gid, @"Original body", nil)];
    request = RecallRequest(gid); delivery = Begin(service, request, final);
    WaitFor(^BOOL { return gOriginalCalls == 1; }, @"native starts before expiry");
    nativePending = gPending;
    [service serviceExtensionTimeWillExpire];
    NSCAssert(gOriginalCalls == 1 && gExpiryCalls == 0 && delivery.calls == 1 &&
              [delivery.result.body isEqual:@"Original body"],
              @"Recovery expiry completes the saved handler even after native has started");
    CheckMetadata(delivery.result, request.content); CheckRequest(request);
    UNNotificationContent *expiryResult = delivery.result;
    nativePending(final);
    NSCAssert(delivery.calls == 1 && delivery.result == expiryResult, @"A late native result after expiry is ignored");

    ResetRecovery(); gExpireAtNativeEntry = YES;
    gDelivered = @[Delivered(gid, @"Original before native handler storage", nil)];
    request = RecallRequest(gid); delivery = Begin(service, request, final);
    WaitFor(^BOOL { return delivery.calls == 1; }, @"expiry between native entry and handler storage");
    NSCAssert(gOriginalCalls == 1 && gExpiryCalls == 0 &&
              [delivery.result.body isEqual:@"Original before native handler storage"],
              @"The recovery fallback remains live across the native-starting window and ignores its later callback");
    CheckMetadata(delivery.result, request.content);

    ResetRecovery(); gKeepUnsent = NO; gDefer = YES;
    request = RecallRequest(gid); delivery = Begin(service, request, final);
    [service serviceExtensionTimeWillExpire];
    NSCAssert(gOriginalCalls == 1 && gExpiryCalls == 1 && delivery.calls == 1,
              @"Without recovery, native still owns the extension-expiry path");
    CheckFallback(delivery.result, final);

    for (NSNumber *queryDelay in @[@0.32, @0.38]) {
        ResetRecovery(); gQueryDefer = YES;
        delivery = Begin(service, RecallRequest(gid), final);
        void (^queryPending)(NSArray *) = gQueryPending; gQueryPending = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(queryDelay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ queryPending(@[Delivered(gid, @"Deadline race body", nil)]); });
        Pump(0.43);
        NSCAssert(delivery.calls == 1 && gOriginalCalls == 1,
                  @"Query and deadline may each win without starting native or its handler twice");
        if (queryDelay.doubleValue < 0.35)
            NSCAssert([delivery.result.body isEqual:@"Deadline race body"], @"A query completing before the deadline recovers");
        else CheckFallback(delivery.result, final);
    }

    // Exercise both contenders concurrently, allowing either legal winner without a second delivery.
    for (NSUInteger attempt = 0; attempt < 8; attempt++) {
        ResetRecovery(); gQueryDefer = YES;
        delivery = Begin(service, RecallRequest(gid), final);
        expired = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [service serviceExtensionTimeWillExpire]; dispatch_semaphore_signal(expired);
        });
        CompleteQuery(@[Delivered(gid, @"Race original body", nil)]);
        WaitFor(^BOOL { return dispatch_semaphore_wait(expired, DISPATCH_TIME_NOW) == 0; }, @"expiry/query race finishes");
        Pump(0.003);
        NSCAssert(delivery.calls == 1 && gOriginalCalls <= 1 && gExpiryCalls <= gOriginalCalls,
                  @"Exactly one query/expiry winner; native expiry runs only after native completed and cleared recovery");
    }

    ResetRecovery();
    request = RecallRequest(gid);
    [service didReceiveNotificationRequest:request withContentHandler:nil];
    NSCAssert(gOriginalCalls == 1 && gQueryCalls == 0 && gNilHandlerForwarded,
              @"A nil final handler is passed directly to native even for an eligible recall");
}

int main(void) { @autoreleasepool {
    NSString *language = NSProcessInfo.processInfo.environment[@"TP_TEST_LANGUAGE"];
    NSDictionary *expected = @{
        @"zh-CN": @"一条消息已被撤回", @"zh-Hans": @"一条消息已被撤回",
        @"zh-TW": @"一則訊息已被收回", @"zh-HK": @"一則訊息已被收回", @"zh-Hant": @"一則訊息已被收回",
        @"en": @"A message was unsent", @"fr": @"A message was unsent",
        @"ja": @"メッセージの送信が取り消されました", @"ko": @"메시지 전송이 취소되었습니다",
    };
    NSCAssert([NSLocale.preferredLanguages.firstObject isEqual:language] && expected[language],
              @"Use the actual requested system language: %@", NSLocale.preferredLanguages);
    gTranslation = expected[language]; gTranslates = ![gTranslation isEqual:@"A message was unsent"];
    NSCAssert([TPUnsentNotificationBody() isEqual:gTranslation], @"Choose the built-in %@ text without a resource bundle", language);
    FBNotificationService *service = [FBNotificationService new];
    NSString *marker = @"text_post_app_recall_notif";
    NSCAssert(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.burbn.barcelona.NotificationServiceExtension"],
              @"Exercise the real constructor without the original app bundle identifier");
    if ([NSProcessInfo.processInfo.environment[@"TP_TEST_EXPECT_NO_HOOK"] boolValue]) {
        NSCAssert([NSProcessInfo.processInfo.processName isEqual:@"Threads"] && gTranslates,
                  @"Exercise the real main-app process boundary in a translated language");
        UNNotificationContent *content = Content(@"A message was unsent", marker);
        NSCAssert(Deliver(service, content, content) == content, @"Do not install the notification hook in the main app");
        puts("notification constructor process boundary: PASS (Threads main process is untouched)");
        return 0;
    }
    NSCAssert([NSProcessInfo.processInfo.processName isEqual:@"BarcelonaNotificationExtension"],
              @"Exercise the real extension constructor process gate");
    for (id other in @[[NSNull null], @"other", @"text_post_app_recall_notif_extra", @1]) {
        UNNotificationContent *ordinary = Content(@"A message was unsent", other == NSNull.null ? nil : other);
        NSCAssert(Deliver(service, ordinary, ordinary) == ordinary,
                  @"Ordinary messages with the same English sentence are untouched");
    }
    for (NSString *body in @[@"A message was unsent", @"A message was unsent."]) {
        UNNotificationContent *entry = Content(body, marker);
        gUseForwardedContent = YES;
        UNNotificationContent *entryResult = Deliver(service, entry, nil);
        NSCAssert(gTranslates ? entryResult != entry && [entryResult.body isEqual:gTranslation] : entryResult == entry,
                  @"Localize forwarded entry content only when the native final handler returns it");
        NSCAssert([entry.body isEqual:body], @"Do not mutate the original request body");
        CheckMetadata(entryResult, entry);
        gUseForwardedContent = NO;
        for (NSUInteger markers = 1; markers <= 3; markers++) {
            UNNotificationContent *original = Content(@"Original body", (markers & 1) ? marker : nil);
            UNNotificationContent *final = Content(body, (markers & 2) ? marker : nil);
            UNNotificationContent *result = Deliver(service, original, final);
            if (gTranslates) {
                NSCAssert(result != final && [result isKindOfClass:UNMutableNotificationContent.class] &&
                          [result.body isEqual:gTranslation], @"Either exact original or final marker localizes both exact English bodies");
                CheckMetadata(result, final);
            } else NSCAssert(result == final, @"English and unsupported system languages preserve the native result object");
            NSCAssert([final.body isEqual:body], @"Do not mutate the native result");
        }
        UNNotificationContent *final = Content(body, nil);
        UNNotificationContent *result = Deliver(service, entry, final);
        NSCAssert(gTranslates ? [result.body isEqual:gTranslation] && result != final : result == final,
                  @"The original marker still identifies the final body if its marker is removed");
    }
    for (NSString *body in @[@"A message was unsent!", @"A message was unsent\n", @"a message was unsent",
                            @"Prefix A message was unsent", @"一条消息已被撤回", @""]) {
        UNNotificationContent *content = Content(body, marker);
        NSCAssert(Deliver(service, content, content) == content, @"All other bodies are untouched");
    }
    UNNotificationContent *nilBody = Content(nil, marker);
    NSCAssert(Deliver(service, nilBody, nilBody) == nilBody, @"Nil bodies are untouched");
    UNNotificationContent *unsent = Content(@"A message was unsent.", marker);
    NSCAssert(Deliver(service, unsent, nil) == nil && Deliver(service, nil, nil) == nil &&
              DeliverRequest(service, nil, nil) == nil, @"Nil native content, request content and requests are forwarded once");
    UNNotificationRequest *request = Request(unsent);
    NSUInteger originalsBefore = gOriginalCalls;
    [service didReceiveNotificationRequest:request withContentHandler:nil];
    NSCAssert(gNilHandlerForwarded && gOriginalCalls == originalsBefore + 1 && gReceivedRequest == request,
              @"Nil handlers and their original requests pass through");
    gDefer = YES;
    __block NSUInteger asynchronousCalls = 0; __block UNNotificationContent *asynchronousResult;
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    [service didReceiveNotificationRequest:request withContentHandler:^(UNNotificationContent *content) {
        asynchronousCalls++; asynchronousResult = content; dispatch_semaphore_signal(completed);
    }];
    CheckRequest(request);
    NSCAssert(asynchronousCalls == 0 && gPending, @"Do not preempt the native asynchronous callback");
    void (^pending)(UNNotificationContent *) = gPending; gPending = nil;
    UNNotificationContent *deferredFinal = Content(@"A message was unsent", nil);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ pending(deferredFinal); });
    NSCAssert(dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0 && asynchronousCalls == 1,
              @"Preserve deferred delivery and complete the original handler once");
    NSCAssert(gTranslates ? [asynchronousResult.body isEqual:gTranslation] && asynchronousResult != deferredFinal : asynchronousResult == deferredFinal,
              @"The deferred final callback follows the original marker and system language");
    CheckMetadata(asynchronousResult, deferredFinal);
    RunRecoveryTests(service);
    printf("notification recovery/localization: PASS (%s, actual hook/ctor/NSLocale, exact gid, metadata, switch, deadline/query/expiry races; local UN stubs, no device push)\n", language.UTF8String);
} return 0; }
