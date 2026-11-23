#import "TPMusicAttachment.h"
#import <math.h>

static NSDictionary *TPMusicDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static NSString *TPMusicString(id value) {
    return [value isKindOfClass:NSString.class] && [(NSString *)value length] ? value : nil;
}

// Walks arbitrary nesting so a schema change (extra wrapper, renamed container)
// cannot silently disable the attachment again.
static void TPMusicCollect(id node, NSString *key, NSUInteger depth, NSMutableArray *out) {
    if (!out || depth > 6) return;
    if ([node isKindOfClass:NSDictionary.class]) {
        for (id child in (NSDictionary *)node) {
            id value = ((NSDictionary *)node)[child];
            if ([child isKindOfClass:NSString.class] && [(NSString *)child isEqualToString:key]) {
                NSString *string = TPMusicString(value);
                if (string && ![out containsObject:string]) [out addObject:string];
            }
            TPMusicCollect(value, key, depth + 1, out);
        }
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)node) TPMusicCollect(value, key, depth + 1, out);
    }
}

// Text nodes arrive either as a plain string or as { "text": "..." }.
static void TPMusicCollectText(id node, NSString *key, NSUInteger depth, NSMutableArray *out) {
    if (!out || depth > 6) return;
    if ([node isKindOfClass:NSDictionary.class]) {
        for (id child in (NSDictionary *)node) {
            id value = ((NSDictionary *)node)[child];
            if ([child isKindOfClass:NSString.class] && [(NSString *)child isEqualToString:key]) {
                NSString *text = TPMusicString(value) ?: TPMusicString(TPMusicDictionary(value)[@"text"]);
                if (text && ![out containsObject:text]) [out addObject:text];
            }
            TPMusicCollectText(value, key, depth + 1, out);
        }
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)node) TPMusicCollectText(value, key, depth + 1, out);
    }
}

static void TPMusicCollectNumber(id node, NSString *key, NSUInteger depth, NSMutableArray *out) {
    if (!out || depth > 6) return;
    if ([node isKindOfClass:NSDictionary.class]) {
        for (id child in (NSDictionary *)node) {
            id value = ((NSDictionary *)node)[child];
            if ([child isKindOfClass:NSString.class] && [(NSString *)child isEqualToString:key] &&
                [value respondsToSelector:@selector(doubleValue)]) {
                [out addObject:@([value doubleValue])];
            }
            TPMusicCollectNumber(value, key, depth + 1, out);
        }
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)node) TPMusicCollectNumber(value, key, depth + 1, out);
    }
}

static NSDictionary *TPMusicConsumableVideo(NSDictionary *info) {
    return TPMusicDictionary(info[@"music_consumable_video"]);
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

static NSURL *TPMusicURLFromManifest(NSString *manifest) {
    if (!manifest.length) return nil;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[manifest dataUsingEncoding:NSUTF8StringEncoding]];
    if (!parser) return nil;
    TPMusicManifest *delegate = [TPMusicManifest new];
    parser.delegate = delegate;
    parser.shouldResolveExternalEntities = NO;
    if (![parser parse]) return nil;
    return delegate.URL;
}

static NSArray<NSString *> *TPMusicManifests(NSDictionary *info) {
    NSMutableArray *out = [NSMutableArray array];
    NSDictionary *video = TPMusicConsumableVideo(info);
    NSDictionary *documented = TPMusicDictionary(TPMusicDictionary(video[@"audio_metadata"])[@"audio_asset"]);
    NSString *manifest = TPMusicString(documented[@"dash_manifest"]);
    if (manifest) [out addObject:manifest];
    NSMutableArray *found = [NSMutableArray array];
    TPMusicCollect(info, @"dash_manifest", 0, found);
    for (NSString *candidate in found) if (![out containsObject:candidate]) [out addObject:candidate];
    return out;
}

static NSString *TPMusicFirstText(NSDictionary *info, NSString *key, NSString *fallbackKey) {
    NSMutableArray *found = [NSMutableArray array];
    TPMusicCollectText(info, key, 0, found);
    if (!found.count && fallbackKey) TPMusicCollectText(info, fallbackKey, 0, found);
    return found.firstObject;
}

@implementation TPMusicAttachment
+ (instancetype)attachmentWithDictionary:(id)value {
    NSDictionary *info = TPMusicDictionary(value);
    if (!info || !TPMusicConsumableVideo(info)) return nil;
    NSURL *URL = nil;
    for (NSString *manifest in TPMusicManifests(info)) {
        URL = TPMusicURLFromManifest(manifest);
        if (URL) break;
    }
    if (!URL) return nil;
    NSString *title = TPMusicFirstText(info, @"display_title", @"title");
    NSString *artist = TPMusicFirstText(info, @"display_artist", @"artist");
    NSMutableArray *starts = [NSMutableArray array];
    TPMusicCollectNumber(info, @"audio_start_time_in_ms", 0, starts);
    double seconds = starts.count ? [starts.firstObject doubleValue] / 1000.0 : 0;
    TPMusicAttachment *result = [self new];
    result->_title = [(title ?: artist) copy] ?: @"";
    result->_artist = [(artist ?: @"") copy];
    result->_URL = URL;
    result->_startTime = isfinite(seconds) && seconds > 0 ? seconds : 0;
    return result;
}

+ (NSDictionary<NSString *, id> *)diagnosticsForDictionary:(id)value {
    NSDictionary *info = TPMusicDictionary(value);
    NSDictionary *video = info ? TPMusicConsumableVideo(info) : nil;
    id available = info[@"is_available_for_consumption"];
    NSArray *manifests = info ? TPMusicManifests(info) : @[];
    BOOL playable = NO;
    for (NSString *manifest in manifests) {
        if (TPMusicURLFromManifest(manifest)) { playable = YES; break; }
    }
    return @{
        @"recognized": @(video != nil),
        @"denied": @([available respondsToSelector:@selector(boolValue)] && ![available boolValue]),
        @"manifests": @(manifests.count),
        @"playable": @(playable),
        @"title": @(TPMusicFirstText(info, @"display_title", @"title").length > 0),
        @"error": TPMusicString(info[@"error_code"]) ?: @"",
        @"muted": TPMusicString(info[@"muted_reason"]) ?: @"",
    };
}
@end
