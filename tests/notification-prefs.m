#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>
#import "../TPNotificationPrefs.h"
#import "../TPPrefs.h"

// Keep the existing preference API under test without touching the user's real defaults domain.
@interface TPTestDefaults : NSObject
@property (strong) NSMutableDictionary *values;
@end
@implementation TPTestDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { self.values[key] = @(value); }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { self.values[key] = @(value); }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
@end
static TPTestDefaults *gDefaults;
static NSUserDefaults *TestDefaults(id self, SEL selector) { return (NSUserDefaults *)(id)gDefaults; }

static void WriteState(NSURL *url, id state) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NSCAssert([data writeToURL:url atomically:YES], @"Write test state");
}

int main(void) { @autoreleasepool {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tp-notification-prefs-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    NSURL *state = [[root URLByAppendingPathComponent:@"ThreadsPulse" isDirectory:YES] URLByAppendingPathComponent:@"notification-prefs.plist"];
    TPNotificationPrefsSetTestingContainerURL(root);
    NSCAssert(!TPNotificationPrefsReadKeepUnsent(), @"Missing file is off");
    NSCAssert(TPNotificationPrefsWriteKeepUnsent(YES) && TPNotificationPrefsReadKeepUnsent(), @"Persist and read on");
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:state];
    NSCAssert(saved.count == 1 && saved[@"keepUnsent"] == (__bridge id)kCFBooleanTrue, @"Only the explicit boolean is mirrored");
    NSCAssert(TPNotificationPrefsWriteKeepUnsent(NO) && !TPNotificationPrefsReadKeepUnsent(), @"Persist and read off");
    for (id invalid in @[@{}, @[], @{@"keepUnsent": @"YES"}, @{@"keepUnsent": @1}]) {
        WriteState(state, invalid);
        NSCAssert(!TPNotificationPrefsReadKeepUnsent(), @"Malformed or non-boolean state is off");
    }
    NSCAssert([[@"not a plist" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:state atomically:YES], @"Write malformed bytes");
    NSCAssert(!TPNotificationPrefsReadKeepUnsent(), @"Malformed bytes are off");
    NSCAssert(TPNotificationPrefsWriteKeepUnsent(YES), @"Restore valid state");
    if (geteuid() != 0) {
        NSCAssert(chmod(state.fileSystemRepresentation, 0000) == 0, @"Make state unreadable");
        NSCAssert(!TPNotificationPrefsReadKeepUnsent(), @"Unreadable state is off");
        NSCAssert(chmod(state.fileSystemRepresentation, 0600) == 0, @"Restore permissions");
    }
    NSCAssert([NSFileManager.defaultManager removeItemAtURL:state error:NULL], @"Remove saved file");
    NSCAssert(!TPNotificationPrefsReadKeepUnsent(), @"Removed file is off without a cached YES");
    TPNotificationPrefsSetTestingContainerURL(nil);
    NSCAssert(!TPNotificationPrefsReadKeepUnsent() && !TPNotificationPrefsWriteKeepUnsent(YES), @"Unavailable group is off and cannot write");
    TPNotificationPrefsSetTestingContainerURL(root);

    gDefaults = [TPTestDefaults new];
    Method getter = class_getClassMethod(TPPrefs.class, @selector(defaults));
    IMP original = method_setImplementation(getter, (IMP)TestDefaults);
    [TPPrefs setBool:YES forKey:TPKeyKeepUnsent];
    NSCAssert(TPNotificationPrefsReadKeepUnsent(), @"The production KeepUnsent setter mirrors on");
    [TPPrefs setBool:NO forKey:TPKeyBlockAds];
    NSCAssert(TPNotificationPrefsReadKeepUnsent(), @"Other settings do not change the mirror");
    [TPPrefs setBool:NO forKey:TPKeyKeepUnsent];
    NSCAssert(!TPNotificationPrefsReadKeepUnsent(), @"The production KeepUnsent setter mirrors off");
    [TPPrefs setBool:YES forKey:TPKeyKeepUnsent];
    [TPPrefs resetAll];
    NSCAssert(!TPNotificationPrefsReadKeepUnsent() && ![TPPrefs boolForKey:TPKeyKeepUnsent], @"Reset clears both stores");
    NSData *enabledImport = [NSJSONSerialization dataWithJSONObject:@{@"settings": @{TPKeyKeepUnsent: @YES}} options:0 error:NULL];
    NSCAssert([TPPrefs importJSONData:enabledImport] == 1 && TPNotificationPrefsReadKeepUnsent(), @"Import reaches the real setter and mirror");
    NSData *disabledImport = [NSJSONSerialization dataWithJSONObject:@{@"settings": @{TPKeyKeepUnsent: @NO}} options:0 error:NULL];
    NSCAssert([TPPrefs importJSONData:disabledImport] == 1 && !TPNotificationPrefsReadKeepUnsent(), @"Import mirrors off");
    method_setImplementation(getter, original);
    [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
    puts("notification preference mirror: PASS (real Foundation/files; in-memory source defaults, no device/AppGroup entitlement test)");
} return 0; }
