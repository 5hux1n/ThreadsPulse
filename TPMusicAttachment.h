#import <Foundation/Foundation.h>

@interface TPMusicAttachment : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *artist;
@property (nonatomic, strong, readonly) NSURL *URL;
@property (nonatomic, readonly) NSTimeInterval startTime;
+ (instancetype)attachmentWithDictionary:(id)dictionary;
@end
