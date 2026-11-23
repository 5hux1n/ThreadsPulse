#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL TPNotificationPrefsReadKeepUnsent(void);
FOUNDATION_EXPORT BOOL TPNotificationPrefsWriteKeepUnsent(BOOL enabled);

#if TP_NOTIFICATION_PREFS_TESTING
FOUNDATION_EXPORT void TPNotificationPrefsSetTestingContainerURL(NSURL * _Nullable url);
#endif

NS_ASSUME_NONNULL_END
