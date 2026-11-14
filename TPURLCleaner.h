#import <Foundation/Foundation.h>

@interface TPURLCleaner : NSObject
+ (NSURL *)cleanURL:(NSURL *)url;
+ (BOOL)isRedirectHost:(NSString *)host;
+ (NSString *)cleanString:(NSString *)string;
@end
