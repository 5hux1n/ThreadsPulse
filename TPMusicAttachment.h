#import <Foundation/Foundation.h>

@interface TPMusicAttachment : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *artist;
@property (nonatomic, strong, readonly) NSURL *URL;
@property (nonatomic, readonly) NSTimeInterval startTime;
+ (instancetype)attachmentWithDictionary:(id)dictionary;
// Explains why attachmentWithDictionary: accepted or rejected a payload.
// Keys: recognized, denied, manifest, title, error, muted.
+ (NSDictionary<NSString *, id> *)diagnosticsForDictionary:(id)dictionary;
@end
