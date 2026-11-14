#import <Foundation/Foundation.h>

@interface OpenInThreadsHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation OpenInThreadsHandler
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    [context completeRequestReturningItems:@[] completionHandler:nil];
}
@end
