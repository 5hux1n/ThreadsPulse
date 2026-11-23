#import <Foundation/Foundation.h>
#import "TPMusicAttachment.h"
static NSDictionary *info(NSString *manifest, id available, id start) {
    return @{ @"is_available_for_consumption": available,
              @"music_consumable_video": @{ @"audio_start_time_in_ms": start,
                  @"audio_metadata": @{ @"audio_asset": @{
                      @"display_title": @{ @"text": @"囚笼" },
                      @"display_artist": @{ @"text": @"Ashe" },
                      @"dash_manifest": manifest } } } };
}
// Shape captured from Threads 410 for a rights-restricted viewer on 2026-11-22.
static NSDictionary *mutedInfo(void) {
    return @{ @"error_code": @"MUSIC_RIGHTS_NOT_LAUNCHED_COUNTRY",
              @"muted_reason": @"DENY_IF_NOT_IN_MR_LAUNCHED_GEOS",
              @"is_available_for_consumption": @NO,
              @"music_consumable_video": @{ @"audio_overlap_duration_in_ms": @0,
                  @"media_id": @"4035721295623286158",
                  @"audio_start_time_in_ms": @61000,
                  @"audio_start_time_in_composition_in_ms": @0,
                  @"lyrics_usage_type_as_string": @"NO_USAGE" } };
}
int main(void) { @autoreleasepool {
    NSString *xml = @"<MPD><Period><AdaptationSet mimeType='audio/mp4'><Representation><BaseURL>https://media.example.test/audio.mp4?a=1&amp;b=2</BaseURL></Representation></AdaptationSet></Period></MPD>";
    TPMusicAttachment *a = [TPMusicAttachment attachmentWithDictionary:info(xml, @YES, @1500)];
    NSCAssert([a.title isEqualToString:@"囚笼"] && [a.artist isEqualToString:@"Ashe"], @"Metadata");
    NSCAssert([a.URL.absoluteString isEqualToString:@"https://media.example.test/audio.mp4?a=1&b=2"], @"Signed query must survive XML decoding");
    NSCAssert(a.startTime == 1.5, @"Shared audio offset");
    TPMusicAttachment *flagged = [TPMusicAttachment attachmentWithDictionary:info(xml, @NO, @0)];
    NSCAssert([flagged.URL isEqual:a.URL], @"A valid audio asset remains usable when availability is false");
    NSMutableDictionary *restrictedWithAudio = [mutedInfo() mutableCopy];
    restrictedWithAudio[@"music_consumable_video"] = info(xml, @NO, @0)[@"music_consumable_video"];
    NSCAssert([TPMusicAttachment attachmentWithDictionary:restrictedWithAudio] != nil, @"Region error metadata does not discard an existing audio asset");
    NSCAssert([[TPMusicAttachment diagnosticsForDictionary:restrictedWithAudio][@"denied"] boolValue], @"Diagnostics retain the original availability mark");
    NSCAssert(![TPMusicAttachment attachmentWithDictionary:info(@"<MPD><BaseURL>file:///tmp/a</BaseURL></MPD>", @YES, @0)], @"Reject local URLs");
    NSCAssert(![TPMusicAttachment attachmentWithDictionary:info(@"<MPD><BaseURL>https://media.example.test/a</BaseURL></MPD>", @YES, @0)], @"Reject malformed manifests");
    NSCAssert(![TPMusicAttachment attachmentWithDictionary:NSNull.null], @"Reject missing objects");
    NSString *mixed = @"<MPD><Period><AdaptationSet mimeType='video/mp4'><Representation><BaseURL>https://media.example.test/video.mp4</BaseURL></Representation></AdaptationSet><AdaptationSet mimeType='audio/mp4'><Representation><BaseURL>https://media.example.test/music.mp4</BaseURL></Representation></AdaptationSet></Period></MPD>";
    NSCAssert([[TPMusicAttachment attachmentWithDictionary:info(mixed, @YES, @0)].URL.lastPathComponent isEqualToString:@"music.mp4"], @"Choose audio rather than the first video representation");
    NSCAssert([TPMusicAttachment attachmentWithDictionary:info(xml, @YES, NSNull.null)].startTime == 0, @"Missing offset");

    // Rights-restricted payload: recognized, but nothing to play and no fake button.
    TPMusicAttachment *muted = [TPMusicAttachment attachmentWithDictionary:mutedInfo()];
    NSCAssert(!muted, @"Muted payload carries no asset");
    NSDictionary *diagnostics = [TPMusicAttachment diagnosticsForDictionary:mutedInfo()];
    NSCAssert([diagnostics[@"recognized"] boolValue], @"Muted payload is still a music attachment");
    NSCAssert([diagnostics[@"denied"] boolValue], @"Diagnostics must report the rights mark");
    NSCAssert([diagnostics[@"manifests"] integerValue] == 0, @"Diagnostics must report the missing manifest");
    NSCAssert([diagnostics[@"error"] isEqualToString:@"MUSIC_RIGHTS_NOT_LAUNCHED_COUNTRY"], @"Diagnostics must keep the server code");

    // Schema drift: extra wrappers, no availability flag, text node instead of display_title.
    NSDictionary *drifted = @{ @"music_consumable_video": @{ @"audio_metadata": @{
        @"audio_asset": @{ @"audio": @{ @"dash_manifest": xml } } } },
        @"title": @"Ashe" };
    TPMusicAttachment *b = [TPMusicAttachment attachmentWithDictionary:drifted];
    NSCAssert(b && [b.URL.absoluteString hasSuffix:@"/audio.mp4?a=1&b=2"], @"Nested manifest stays reachable");
    NSCAssert([b.title isEqualToString:@"Ashe"], @"Fallback title");

    puts("music attachment parser: PASS");
} return 0; }
