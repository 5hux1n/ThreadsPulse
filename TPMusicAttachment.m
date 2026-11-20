#import "TPMusicAttachment.h"
#import <math.h>

static NSDictionary *TPMusicDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static NSString *TPMusicString(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

@interface TPMusicManifest : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) NSMutableString *baseURL;
@property (nonatomic) NSUInteger depth;
@property (nonatomic) NSUInteger audioDepth;
@end
@implementation TPMusicManifest
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)name attributes:(NSDictionary *)attributes {
    self.depth++;
    if (!self.audioDepth && ([attributes[@"mimeType"] hasPrefix:@"audio/"] || [attributes[@"contentType"] isEqualToString:@"audio"] || [attributes[@"codecs"] hasPrefix:@"mp4a"])) self.audioDepth = self.depth;
    // shortcut: single-file audio DASH only; segmented manifests need a separate adapter.
    if ([element isEqualToString:@"BaseURL"] && self.audioDepth) self.baseURL = [NSMutableString string];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.baseURL appendString:string];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)name {
    if ([element isEqualToString:@"BaseURL"] && self.baseURL) {
        NSURL *URL = [NSURL URLWithString:[self.baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        if (!self.URL && [URL.scheme.lowercaseString isEqualToString:@"https"] && URL.host.length) self.URL = URL;
        self.baseURL = nil;
    }
    if (self.audioDepth == self.depth) self.audioDepth = 0;
    self.depth--;
}
@end

@implementation TPMusicAttachment
+ (instancetype)attachmentWithDictionary:(id)value {
    NSDictionary *info = TPMusicDictionary(value);
    id available = info[@"is_available_for_consumption"];
    if (![available respondsToSelector:@selector(boolValue)] || ![available boolValue]) return nil;
    NSDictionary *video = TPMusicDictionary(info[@"music_consumable_video"]);
    NSDictionary *metadata = TPMusicDictionary(video[@"audio_metadata"]);
    NSDictionary *asset = TPMusicDictionary(metadata[@"audio_asset"]);
    NSString *manifest = TPMusicString(asset[@"dash_manifest"]);
    NSString *title = TPMusicString(TPMusicDictionary(asset[@"display_title"])[@"text"]);
    if (!manifest.length || !title.length) return nil;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[manifest dataUsingEncoding:NSUTF8StringEncoding]];
    TPMusicManifest *delegate = [TPMusicManifest new];
    parser.delegate = delegate;
    parser.shouldResolveExternalEntities = NO;
    if (![parser parse] || !delegate.URL) return nil;
    TPMusicAttachment *result = [self new];
    result->_title = [title copy];
    result->_artist = [TPMusicString(TPMusicDictionary(asset[@"display_artist"])[@"text"]) copy] ?: @"";
    result->_URL = delegate.URL;
    id start = video[@"audio_start_time_in_ms"];
    double seconds = [start respondsToSelector:@selector(doubleValue)] ? [start doubleValue] / 1000.0 : 0;
    result->_startTime = isfinite(seconds) && seconds > 0 ? seconds : 0;
    return result;
}
@end
