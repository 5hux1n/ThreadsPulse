// Synthetic fixtures shaped as Foundation JSON containers; these are not device captures.
@interface TPTestNativeUser : NSObject
@property (nonatomic, strong) NSNumber *textPostAppJoinedTime;
@property (nonatomic, strong) NSNumber *textPostAppJoinerNumber;
@property (nonatomic, copy) NSString *textPostAppJoinerNumberLabel;
@end
@implementation TPTestNativeUser @end

static NSDictionary *TPTestParseJSON(id fixture) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:fixture options:0 error:&error];
    NSCAssert(data && !error, @"Fixture must be JSON");
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    NSCAssert(root && !error, @"Decode fixture as the native RootApp callback does");
    NSMutableArray *strings = [NSMutableArray array];
    int budget = 6000;
    TPHarvestStrings(root, 0, [NSMutableSet set], strings, &budget);
    return TPParseStrings(strings);
}

int main(void) { @autoreleasepool {
    NSDictionary *rows = TPTestParseJSON(@{ @"tree": @[
        @[@"Joined", @"July 2023 · #12,345,678"],
        @[@"Based in", @"Taiwan"]
    ] });
    NSCAssert([rows[@"location"] isEqual:@"Taiwan"], @"Read location from a JSON tree");
    NSCAssert([rows[@"joined"] isEqual:@"July 2023"], @"Separate join month from its number");
    NSCAssert([rows[@"number"] isEqual:@"#12,345,678"], @"Preserve the join number");
    NSCAssert(TPHasAuthorDetails(rows), @"Parsed rows are usable author details");

    NSDictionary *state = TPTestParseJSON(@{ @"tree": @[
        @"1", @"gs", @"THREADS_ABOUT_THIS_PROFILE:about_this_profile_country", @"p", @"Taiwan",
        @"2", @"gs", @"THREADS_ABOUT_THIS_PROFILE:about_this_profile_join_date", @"p", @"July 2023"
    ] });
    NSCAssert([state[@"location"] isEqual:@"Taiwan"], @"Read state-only location");
    NSCAssert([state[@"joined"] isEqual:@"July 2023"], @"Read state-only join date");

    NSDictionary *hidden = TPTestParseJSON(@{ @"tree": @[
        @"1", @"gs", @"THREADS_ABOUT_THIS_PROFILE:about_this_profile_country_visibility", @"p", @0,
        @"2", @"gs", @"THREADS_ABOUT_THIS_PROFILE:about_this_profile_country", @"p", @"Taiwan"
    ] });
    NSCAssert(!hidden[@"location"] && [hidden[@"hidden"] boolValue], @"Do not reveal a hidden country");
    NSCAssert(TPHasAuthorDetails(hidden), @"A deliberately hidden country is a valid result");

    NSDictionary *empty = TPTestParseJSON(@{ @"tree": @[] });
    NSDictionary *nameOnly = TPTestParseJSON(@{ @"tree": @[@"Name", @"Example (@example"] });
    NSCAssert([nameOnly[@"u"] isEqual:@"example"], @"Username-only fixture exercises a nonempty parse");
    NSCAssert(!TPHasAuthorDetails(nil) && !TPHasAuthorDetails(empty), @"Empty results are not usable details");
    NSCAssert(!TPHasAuthorDetails(nameOnly), @"A username alone must not be cached as successful details");
    NSCAssert(!TPHasAuthorDetails(@{ @"hidden": @NO }), @"False visibility marker is empty");
    NSCAssert(TPHasAuthorDetails(@{ @"number": @"#123" }), @"A join number is usable details");
    NSDictionary *stateCombined = TPTestParseJSON(@{@"tree": @[
        @"1", @"gs", @"THREADS_ABOUT_THIS_PROFILE:about_this_profile_join_date", @"p", @"July 2023 · #12,345,678"
    ]});
    NSCAssert([stateCombined[@"number"] isEqual:@"#12,345,678"], @"State dates must preserve their ordinal");
    NSDictionary *spans = TPTestParseJSON(@{@"tree": @[@"加入时间", @"2026-11", @"·", @"100M+", @"Based in", @"Taiwan"]});
    NSCAssert([spans[@"joined"] isEqual:@"2026-11"] && [spans[@"number"] isEqual:@"100M+"], @"Read a separate ordinal in the same Joined row");
    NSDictionary *unrelated = TPTestParseJSON(@{@"tree": @[@"Joined", @"July 2023", @"Name", @"#7,551,963"]});
    NSCAssert(!unrelated[@"number"], @"Do not borrow a number from the following row");
    NSDictionary *color = TPTestParseJSON(@{@"tree": @[@"Joined", @"July 2023", @"#000000"]});
    NSCAssert(!color[@"number"], @"An adjacent color without an ordinal separator is not a join number");
    NSCAssert(!TPJoinOrdinal(@"#FF000000") && !TPJoinOrdinal(@"1234567890"), @"Hex letters and bare IDs are not join ordinals");
    NSDictionary *ordinalState = TPTestParseJSON(@{@"tree": @[@"1", @"gs", @"THREADS_ABOUT_THIS_PROFILE:joiner_number", @"p", @2000000000]});
    NSCAssert(!ordinalState[@"joined"], @"A numeric ordinal must never become a timestamp");

    NSCalendar *greg = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDate *referenceDate = [greg dateFromComponents:({ NSDateComponents *c = [NSDateComponents new]; c.year = 2026; c.month = 11; c.day = 19; c; })];
    NSCAssert(TPIsNewAccountAtDate(@"2026-11", referenceDate) && TPIsNewAccountAtDate(@"2026年9月", referenceDate), @"Same month and two months earlier are NEW");
    NSCAssert(TPIsNewAccountAtDate(@"October 2026", referenceDate) && TPIsNewAccountAtDate(@"2026년 10월", referenceDate), @"Preserve original English and Korean support");
    NSCAssert(!TPIsNewAccountAtDate(@"2026-08", referenceDate) && !TPIsNewAccountAtDate(@"2026-12", referenceDate) && !TPIsNewAccountAtDate(@"2026-13", referenceDate), @"Old, future and invalid months are not NEW");
    NSDictionary *partialCache = @{@"v": @4, @"location": @"Taiwan"};
    NSCAssert(TPNeedsLegacyCacheRefresh(partialCache, YES) && !TPNeedsLegacyCacheRefresh(partialCache, NO), @"Only old 410 partial caches need one refresh");
    NSCAssert(!TPNeedsLegacyCacheRefresh(@{@"v": @5, @"location": @"Taiwan"}, YES), @"Do not repeatedly refresh genuinely partial responses");

    TPTestNativeUser *user = [TPTestNativeUser new];
    user.textPostAppJoinedTime = @([referenceDate timeIntervalSince1970]);
    user.textPostAppJoinerNumber = @7551963;
    NSDictionary *native = TPJoinInfoForUser(user);
    NSCAssert([native[@"number"] isEqual:@"#7,551,963"] && TPIsNewAccountAtDate(native[@"joined"], referenceDate), @"Read the native user's join time and ordinal together");
    user.textPostAppJoinerNumberLabel = @"100M+";
    NSCAssert([TPJoinInfoForUser(user)[@"number"] isEqual:@"100M+"], @"Prefer the server's formatted ordinal label");
    user.textPostAppJoinedTime = @([referenceDate timeIntervalSince1970] * 1000);
    NSCAssert([TPJoinInfoForUser(user)[@"joined"] isEqual:native[@"joined"]], @"Seconds and milliseconds yield the same month");
    puts("author info JSON harvesting and parser: PASS (synthetic fixtures)");
} return 0; }
