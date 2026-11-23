#import <Foundation/Foundation.h>

static NSString *const TPKeyBlockAds = @"tp_block_ads";
static BOOL gBlocked;
static NSUInteger gDeliveries;
static unsigned long long gContext;
static NSArray *gArguments;
#define TPL(s) (s)
static void TPDebug(NSString *message) {}

@interface TPPrefs : NSObject
+ (BOOL)boolForKey:(NSString *)key;
@end
@implementation TPPrefs
+ (BOOL)boolForKey:(NSString *)key { return [key isEqual:TPKeyBlockAds] && gBlocked; }
@end

@interface IGAdInsertionHandler : NSObject
- (void)deliverSponsoredItemsWithPosts:(id)posts deliveryContext:(unsigned long long)context
        containerModule:(id)module surfaceExtraLoggingDicts:(id)surface
        extraLoggingDict:(id)extra requestMetadata:(id)metadata
        adRequestExtraInfo:(id)requestInfo acpContext:(id)acp;
@end
@implementation IGAdInsertionHandler
- (void)deliverSponsoredItemsWithPosts:(id)posts deliveryContext:(unsigned long long)context
        containerModule:(id)module surfaceExtraLoggingDicts:(id)surface
        extraLoggingDict:(id)extra requestMetadata:(id)metadata
        adRequestExtraInfo:(id)requestInfo acpContext:(id)acp {
    gDeliveries++;
    gContext = context;
    gArguments = @[posts, module, surface, extra, metadata, requestInfo, acp];
}
@end

// PRODUCTION_AD_HOOK

int main(void) { @autoreleasepool {
    IGAdInsertionHandler *handler = [IGAdInsertionHandler new];
    NSMutableArray *arguments = [NSMutableArray array];
    for (NSUInteger i = 0; i < 7; i++) [arguments addObject:[NSObject new]];
    unsigned long long context = 0xfedcba9876543210ULL;
    void (^deliver)(void) = ^{
        [handler deliverSponsoredItemsWithPosts:arguments[0] deliveryContext:context
                containerModule:arguments[1] surfaceExtraLoggingDicts:arguments[2]
                extraLoggingDict:arguments[3] requestMetadata:arguments[4]
                adRequestExtraInfo:arguments[5] acpContext:arguments[6]];
    };
    deliver();
    NSCAssert(gDeliveries == 1 && gContext == context, @"Disabled blocking preserves delivery and its 64-bit context");
    NSCAssert([gArguments isEqual:arguments], @"Forward every original object unchanged");
    gBlocked = YES;
    deliver();
    NSCAssert(gDeliveries == 1, @"Enabled blocking prevents sponsored delivery");
    gBlocked = NO;
    deliver();
    NSCAssert(gDeliveries == 2 && gContext == context && [gArguments isEqual:arguments], @"Turning blocking off immediately restores delivery");
    puts("ad delivery Logos hook: PASS (local stub, no device traffic)");
} return 0; }
