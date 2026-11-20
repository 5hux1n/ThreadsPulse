#import "TPNotificationPrefs.h"
#import <TargetConditionals.h>

#if TP_NOTIFICATION_PREFS_TESTING
static NSURL *gTPNotificationTestingContainerURL;
void TPNotificationPrefsSetTestingContainerURL(NSURL *url) {
    gTPNotificationTestingContainerURL = url;
}
#endif

static NSURL *TPNotificationPrefsURL(void) {
#if TP_NOTIFICATION_PREFS_TESTING
    NSURL *container = gTPNotificationTestingContainerURL;
#else
    NSURL *container = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.burbn.instagram"];
#endif
    return [[container URLByAppendingPathComponent:@"ThreadsPulse" isDirectory:YES]
            URLByAppendingPathComponent:@"notification-prefs.plist"];
}

BOOL TPNotificationPrefsReadKeepUnsent(void) {
    NSURL *url = TPNotificationPrefsURL();
    if (!url) return NO;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return NO;
    id settings = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if (![settings isKindOfClass:NSDictionary.class]) return NO;
    id value = settings[@"keepUnsent"];
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() && [value boolValue];
}

BOOL TPNotificationPrefsWriteKeepUnsent(BOOL enabled) {
    NSURL *url = TPNotificationPrefsURL();
    if (!url) return NO;
    NSDictionary *attributes = nil;
    NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IOS
    // Notifications still need the saved switch while the phone is locked after its first unlock.
    attributes = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    if (![NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent
                               withIntermediateDirectories:YES attributes:attributes error:NULL]) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"keepUnsent": @(enabled)}
                                                            format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    return data && [data writeToURL:url options:options error:NULL];
}
