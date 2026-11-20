#import "TPAuthorInfo.h"
#import "TPPrefs.h"
#import "TPUI.h"
#import "TPHUD.h"
#import "TPLocalization.h"
#import "TPVersion.h"
#import "TPDownloader.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <malloc/malloc.h>
#import <dlfcn.h>

NSString *const TPAuthorInfoDidUpdateNotification = @"TPAuthorInfoDidUpdateNotification";
void (^TPAuthorOpenProfile)(NSString *username);

static NSString *TPFlagForCountry(NSString *name);
static NSString *const kAppID        = @"com.bloks.www.text_post_app.about_this_profile_async_action";
static NSString *const kLegacyAppID  = @"com.bloks.www.text_post_app.about_this_profile_bottom_sheet";
static NSString *const kCacheKey     = @"tp_author_cache";
static NSString *const kPausedKey    = @"tp_author_paused_until";
static NSString *const kVariantKey   = @"tp_author_param_format";

static const NSTimeInterval kDelay          = 1.5;            // seconds between requests
static const NSTimeInterval kLegacyDelay    = 0.75;
static const NSTimeInterval kCooldown       = 60 * 60;        // rate-limit pause
static const NSTimeInterval kTTLLocation    = 21 * 86400;     // entries with a location
static const NSTimeInterval kTTLNoLocation  = 1 * 86400;      // entries without one
static const NSTimeInterval kTTLFailure     = 30 * 60;        // failed lookups
static const NSTimeInterval kTimeout        = 45;
static const NSUInteger     kQueueMax       = 10;
static const NSUInteger     kCacheMax       = 3000;
static const NSUInteger     kSessionMax     = 400;            // hard cap per app launch

static NSMutableDictionary<NSString *, NSDictionary *> *gCache;
static NSMutableArray<NSString *> *gQueue;
static NSMutableSet<NSString *> *gPending;
static id gObjectSet;
static BOOL gSelfCall;
static NSString *const kSynthPending  = @"tp_author_synth_pending";
static NSString *const kSynthDisabled = @"tp_author_synth_disabled";
static __weak id gUserSession;
static id gPandoService;
static id gPandoConsistency;
static id gAnalytics;
static id gSyntheticSet;          // object set we built ourselves
static NSInteger gSyntheticSubtype = -1;
static BOOL gSyntheticFailed;
static BOOL gHintShown;
static NSInteger gSyntheticRetries;  // retries of the built object set this launch (bad network)
static NSHashTable *gBadObjectSets;
static NSString *gObjectSetSource;
static BOOL gInFlight;
static NSUInteger gToken;
static NSString *gInFlightPk;
static CFAbsoluteTime gLastRequest;
static NSUInteger gSessionCount;
static NSUInteger gEmptyStreak;
static NSUInteger gSuccessCount;
static BOOL gParserGaveUp;
static BOOL gSaveScheduled;
static BOOL gPumpScheduled;
static NSMutableString *gDiag;

@interface TPAuthorBadgeLabel : UILabel
@property (nonatomic, copy) NSString *pk;
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) CALayer *capsule;   // outline around everything after the NEW tag
@end

static void TPInvalidateAuthorHeader(UIView *host);

@implementation TPAuthorBadgeLabel
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.lineBreakMode = NSLineBreakByTruncatingTail;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(infoChanged:) name:TPAuthorInfoDidUpdateNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(prefsChanged:) name:TPPrefsDidChangeNotification object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)infoChanged:(NSNotification *)n {
    NSString *pk = n.userInfo[@"pk"];
    if (!pk || [pk isEqualToString:self.pk]) {
        TPInvalidateAuthorHeader(self.host);
        [self.host setNeedsLayout];
    }
}
- (void)prefsChanged:(NSNotification *)n {
    NSString *k = n.userInfo[@"key"];
    if ([k hasPrefix:@"tp_author"] || [k isEqualToString:TPKeyTheme]) {
        TPInvalidateAuthorHeader(self.host);
        [self.host setNeedsLayout];
    }
}
@end

@interface TPAuthorInfo ()
+ (void)pump;
@end

static BOOL TPPkOnScreen(NSString *pk);
static BOOL TPHeaderVisible(UIView *host);
static void TPRequeueVisible(void);
static NSDictionary *TPHeaderJoinInfo(NSString *pk);

static BOOL TPIsThreads410(void) {
    static BOOL legacy;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        legacy = [[version componentsSeparatedByString:@"."].firstObject isEqualToString:@"410"];
    });
    return legacy;
}

@implementation TPAuthorInfo

#pragma mark - Diagnostics

+ (void)log:(NSString *)line {
    if (![TPPrefs boolForKey:TPKeyDebugToast] || !line.length) return;
    void (^append)(void) = ^{
        if (!gDiag) gDiag = [NSMutableString string];
        static NSDateFormatter *f;
        if (!f) { f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss"; }
        [gDiag appendFormat:@"%@ %@\n", [f stringFromDate:[NSDate date]], line];
        if (gDiag.length > 14000) [gDiag deleteCharactersInRange:NSMakeRange(0, gDiag.length - 10000)];
    };
    if (NSThread.isMainThread) append(); else dispatch_async(dispatch_get_main_queue(), append);
}

+ (NSString *)diagnostics {
    NSMutableString *s = [NSMutableString stringWithFormat:@"ThreadsPulse %@ · Author Info\n", TP_VERSION];
    [s appendFormat:@"objectSet: %@ (%@)\n", gObjectSet ? NSStringFromClass([gObjectSet class]) : @"none", gObjectSetSource ?: @"-"];
    [s appendFormat:@"variant: %ld  requests: %lu  ok: %lu  emptyStreak: %lu  gaveUp: %d\n",
        (long)[[TPPrefs defaults] integerForKey:kVariantKey], (unsigned long)gSessionCount,
        (unsigned long)gSuccessCount, (unsigned long)gEmptyStreak, gParserGaveUp];
    [s appendFormat:@"built: disabled=%d last=%@ session=%d svc=%d\n", [[TPPrefs defaults] boolForKey:kSynthDisabled],
        [[TPPrefs defaults] stringForKey:@"tp_author_synth_last"] ?: @"-", gUserSession != nil, gPandoService != nil];
    [s appendFormat:@"cached: %lu  queue: %lu  paused: %.0fs\n", (unsigned long)gCache.count, (unsigned long)gQueue.count, [self pausedRemaining]];
    if (gDiag.length) [s appendString:gDiag];
    return s;
}

#pragma mark - Cache

static BOOL TPHasAuthorDetails(NSDictionary *info) {
    return [info[@"location"] length] || [info[@"joined"] length] ||
           [info[@"number"] length] || [info[@"hidden"] boolValue];
}

static BOOL TPNeedsLegacyCacheRefresh(NSDictionary *entry, BOOL legacy) {
    return legacy && [entry[@"v"] integerValue] < 5 && TPHasAuthorDetails(entry) &&
           (![entry[@"joined"] length] || ![entry[@"number"] length]);
}

static void TPLoadCache(void) {
    if (gCache) return;
    // One-time reset: earlier test builds could disable the built object set too eagerly.
    if (![[TPPrefs defaults] boolForKey:@"tp_author_synth_v3"]) {
        [[TPPrefs defaults] setBool:YES forKey:@"tp_author_synth_v3"];
        [[TPPrefs defaults] removeObjectForKey:kSynthDisabled];
        [[TPPrefs defaults] removeObjectForKey:kSynthPending];
    }
    if ([[TPPrefs defaults] boolForKey:kSynthPending] && [[TPPrefs defaults] boolForKey:@"tp_author_synth_worked"]) {
        // It has worked before, so an unfinished try means Threads was closed, not that it crashed.
        [[TPPrefs defaults] removeObjectForKey:kSynthPending];
    }
    if ([[TPPrefs defaults] boolForKey:kSynthPending]) {
        // The previous launch died while trying a built object set.
        [[TPPrefs defaults] removeObjectForKey:kSynthPending];
        [[TPPrefs defaults] setBool:YES forKey:kSynthDisabled];
        [[TPPrefs defaults] setObject:@"app closed or crashed during the try" forKey:@"tp_author_synth_last"];
    }
    gCache = [NSMutableDictionary dictionary];
    gQueue = [NSMutableArray array];
    gPending = [NSMutableSet set];
    NSDictionary *saved = [[TPPrefs defaults] dictionaryForKey:kCacheKey];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    [saved enumerateKeysAndObjectsUsingBlock:^(NSString *pk, NSDictionary *e, BOOL *stop) {
        if (![e isKindOfClass:[NSDictionary class]]) return;
        if ([e[@"joined"] hasPrefix:@"#"]) return;   // bad parse from an earlier build
        if ([e[@"v"] integerValue] < 2 && e[@"joined"]) return;   // saved before the join number was kept
        if ([e[@"v"] integerValue] < 3 && e[@"joined"] && !e[@"location"]) return;   // may be a hidden location
        if ([e[@"v"] integerValue] < 4 && !TPHasAuthorDetails(e)) return; // discard old empty successes, not real profiles
        if (TPNeedsLegacyCacheRefresh(e, TPIsThreads410())) return;
        if ([e[@"x"] doubleValue] > now) gCache[pk] = e;
    }];
}

static void TPSaveCacheSoon(void) {
    if (gSaveScheduled) return;
    gSaveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gSaveScheduled = NO;
        if (gCache.count > kCacheMax) {
            NSArray *keys = [gCache keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [a[@"x"] compare:b[@"x"]];
            }];
            for (NSUInteger i = 0; i < keys.count - kCacheMax; i++) [gCache removeObjectForKey:keys[i]];
        }
        [[TPPrefs defaults] setObject:[gCache copy] forKey:kCacheKey];
    });
}

static NSMutableDictionary<NSString *, NSString *> *gHeaderNames;   // pk -> handle seen in a feed header

static void TPStore(NSString *pk, NSString *location, NSString *joined, NSString *number, BOOL hidden, BOOL failed, NSDictionary *extra) {
    if (![extra[@"u"] length] && gHeaderNames[pk]) {
        NSMutableDictionary *m = [extra mutableCopy] ?: [NSMutableDictionary dictionary];
        m[@"u"] = gHeaderNames[pk];
        extra = m;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableDictionary *e = [NSMutableDictionary dictionary];
    if (location.length) e[@"location"] = location;
    if (joined.length) e[@"joined"] = joined;
    if (number.length) e[@"number"] = number;
    if (hidden && !location.length) e[@"hidden"] = @YES;
    if ([extra[@"u"] length]) e[@"u"] = extra[@"u"];
    if ([extra[@"n"] length]) e[@"n"] = extra[@"n"];
    e[@"v"] = @5;
    failed = failed || !TPHasAuthorDetails(e);
    NSTimeInterval ttl = failed ? kTTLFailure : (location.length ? kTTLLocation : kTTLNoLocation);
    e[@"x"] = @(now + ttl);
    gCache[pk] = e;
    TPSaveCacheSoon();
    [NSNotificationCenter.defaultCenter postNotificationName:TPAuthorInfoDidUpdateNotification object:nil userInfo:@{ @"pk": pk }];
}

#pragma mark - Public state

+ (BOOL)enabled {
    if (![TPPrefs boolForKey:TPKeyAuthorInfo]) return NO;
    return [TPPrefs boolForKey:TPKeyAuthorLocation] || [TPPrefs boolForKey:TPKeyAuthorJoined] || [TPPrefs boolForKey:TPKeyAuthorNewBadge];
}

+ (NSDictionary *)infoForPk:(NSString *)pk {
    if (!pk.length) return nil;
    TPLoadCache();
    NSDictionary *e = gCache[pk];
    if (!e) return nil;
    if ([e[@"x"] doubleValue] < [NSDate date].timeIntervalSince1970) { [gCache removeObjectForKey:pk]; return nil; }
    return e;
}

+ (NSTimeInterval)pausedRemaining {
    NSTimeInterval until = [[TPPrefs defaults] doubleForKey:kPausedKey];
    NSTimeInterval left = until - [NSDate date].timeIntervalSince1970;
    return left > 0 ? left : 0;
}

+ (void)resume {
    [[TPPrefs defaults] removeObjectForKey:kPausedKey];
    gParserGaveUp = NO;
    gEmptyStreak = 0;
    [self log:@"resumed by user"];
    TPRequeueVisible();
    [self pump];
}

+ (void)clearCache {
    TPLoadCache();
    [gCache removeAllObjects];
    [[TPPrefs defaults] removeObjectForKey:kCacheKey];
    [NSNotificationCenter.defaultCenter postNotificationName:TPAuthorInfoDidUpdateNotification object:nil userInfo:@{}];
}

+ (NSUInteger)cachedCount { TPLoadCache(); return gCache.count; }

+ (NSArray<NSDictionary *> *)allEntries {
    TPLoadCache();
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableArray *out = [NSMutableArray array];
    [gCache enumerateKeysAndObjectsUsingBlock:^(NSString *pk, NSDictionary *e, BOOL *stop) {
        if ([e[@"x"] doubleValue] < now) return;
        if (!e[@"location"] && !e[@"hidden"] && !e[@"joined"]) return;   // failed lookups
        NSMutableDictionary *m = [e mutableCopy];
        m[@"pk"] = pk;
        [out addObject:m];
    }];
    return out;
}

+ (NSString *)flagForCountry:(NSString *)name { return TPFlagForCountry(name); }
+ (NSUInteger)sessionRequestCount { return gSessionCount; }

+ (void)noteUserSession:(id)session {
    if (!session) return;
    gUserSession = session;
    dispatch_async(dispatch_get_main_queue(), ^{ [self pump]; });
}
+ (void)noteService:(id)obj kind:(NSString *)kind {
    if (!obj) return;
    if ([kind isEqualToString:@"pando"]) gPandoService = obj;
    else if ([kind isEqualToString:@"consistency"]) gPandoConsistency = obj;
    else if ([kind isEqualToString:@"analytics"]) gAnalytics = obj;
    dispatch_async(dispatch_get_main_queue(), ^{ [self pump]; });
}


// Builds an object set holding the logged-in session, so reading can start without the user
// opening "About this profile" first. Guarded: a crash during the first try disables it for good.

static id TPBuildObjectSet(NSInteger subtype) {

    id session = gUserSession;
    Class OS = objc_getClass("BKObjectSet"), SC = objc_getClass("IGSessionContext");
    if (!session || !OS || !SC) return nil;
    id os = [[OS alloc] init];
    Ivar tiv = class_getInstanceVariable(OS, "_table");
    if (!os || !tiv) return nil;
    NSMapTable *t = object_getIvar(os, tiv);
    if (![t isKindOfClass:[NSMapTable class]]) {
        t = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                      valueOptions:NSPointerFunctionsStrongMemory capacity:8];
        object_setIvar(os, tiv, t);
    }
    id ctx = [[SC alloc] init];
    Ivar us = class_getInstanceVariable(SC, "_loggedInContext_userSession");
    Ivar st = class_getInstanceVariable(SC, "_subtype");
    if (!ctx || !us || !st) return nil;
    object_setIvar(ctx, us, session);
    *(unsigned long long *)((char *)(__bridge void *)ctx + ivar_getOffset(st)) = (unsigned long long)subtype;
    [t setObject:ctx forKey:SC];
    Class foa = objc_getClass("FOAUserSession");
    if (foa) [t setObject:session forKey:foa];
    Class pc;
    if (gPandoService && (pc = objc_getClass("PNPandoGraphQLService"))) [t setObject:gPandoService forKey:pc];
    if (gPandoConsistency && (pc = objc_getClass("PNPandoGraphQLConsistency"))) [t setObject:gPandoConsistency forKey:pc];
    Protocol *alp = objc_getProtocol("FBAnalyticsLogging");
    if (gAnalytics && alp) [t setObject:gAnalytics forKey:(id)alp];
    for (NSString *name in @[@"BKGlobalStateStore", @"BKBloksSessionStore"]) {
        Class c = objc_getClass(name.UTF8String);
        id v = c ? [[c alloc] init] : nil;
        if (v) [t setObject:v forKey:c];
    }
    return os;
}

+ (void)noteObjectSet:(id)objectSet source:(NSString *)source {
    if (!objectSet || gSelfCall || [gBadObjectSets containsObject:objectSet]) return;
    if (objectSet != gObjectSet) [self log:[NSString stringWithFormat:@"objectSet captured from %@ (%@)", source, NSStringFromClass([objectSet class])]];
    gObjectSet = objectSet;
    gObjectSetSource = source;
    if (gQueue.count && !gInFlight) dispatch_async(dispatch_get_main_queue(), ^{ [self pump]; });
}

#pragma mark - Joined date

// Usernames Threads assigns when none is chosen at sign-up: an animal word, a dot and 6-8 digits
// (camel.253044). Word list and rule from lee-su-threads (MIT, see ThirdPartyLicenses). Only that exact form matches.
+ (BOOL)isDefaultUsername:(NSString *)username {
    if (username.length < 8) return NO;
    static NSSet *animals;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        animals = [NSSet setWithArray:@[@"aardvark", @"alligator", @"armadillo", @"badger", @"bat", @"bear", @"camel", @"capybara", @"chameleon", @"cheetah", @"chipmunk", @"crab", @"deer", @"dinosaur", @"dolphin", @"dragon", @"duck", @"elephant", @"elk", @"fox", @"gazelle", @"gecko", @"giraffe", @"goat", @"goose", @"hamster", @"hawk", @"horse", @"iguana", @"jellyfish", @"kangaroo", @"kitty", @"koala", @"lemming", @"leopard", @"lion", @"llama", @"lynx", @"macaque", @"marmoset", @"millipede", @"mongoose", @"moose", @"mouse", @"otter", @"owl", @"panda", @"panther", @"penguin", @"pigeon", @"platypus", @"quail", @"rabbit", @"reindeer", @"rhea", @"rhino", @"scorpion", @"seal", @"sheep", @"shrimp", @"sloth", @"spoonbill", @"squirrel", @"swan", @"tiger", @"turtle", @"unicorn", @"wolf", @"zebra"]];
        re = [NSRegularExpression regularExpressionWithPattern:@"^([a-z]+)\\.(\\d{6,8})$" options:0 error:nil];
    });
    NSString *u = username.lowercaseString;
    NSTextCheckingResult *m = [re firstMatchInString:u options:0 range:NSMakeRange(0, u.length)];
    return m && [animals containsObject:[u substringWithRange:[m rangeAtIndex:1]]];
}

static BOOL TPIsNewAccountAtDate(NSString *joined, NSDate *date) {
    if (!joined.length) return NO;
    NSRegularExpression *yr = [NSRegularExpression regularExpressionWithPattern:@"(\\d{4})" options:0 error:nil];
    NSTextCheckingResult *ym = [yr firstMatchInString:joined options:0 range:NSMakeRange(0, joined.length)];
    if (!ym) return NO;
    NSInteger year = [[joined substringWithRange:[ym rangeAtIndex:1]] integerValue];
    NSInteger month = -1;
    NSRegularExpression *cjk = [NSRegularExpression regularExpressionWithPattern:@"(\\d{1,2})\\s*[月월]" options:0 error:nil];
    NSTextCheckingResult *cm = [cjk firstMatchInString:joined options:0 range:NSMakeRange(0, joined.length)];
    if (cm) month = [[joined substringWithRange:[cm rangeAtIndex:1]] integerValue];
    if (month < 1 && [joined rangeOfString:@"^(19|20)[0-9]{2}-(0[1-9]|1[0-2])$" options:NSRegularExpressionSearch].location != NSNotFound)
        month = [joined substringFromIndex:5].integerValue;
    if (month < 1) {
        NSArray *names = @[@"jan", @"feb", @"mar", @"apr", @"may", @"jun", @"jul", @"aug", @"sep", @"oct", @"nov", @"dec"];
        NSString *low = joined.lowercaseString;
        for (NSUInteger i = 0; i < names.count; i++) if ([low containsString:names[i]]) { month = i + 1; break; }
    }
    NSCalendar *greg = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; // ROC calendar users would get year 115
    if (month < 1) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.locale = NSLocale.currentLocale;
        f.calendar = greg;
        [f setLocalizedDateFormatFromTemplate:@"yMMMM"];
        NSDate *parsed = [f dateFromString:joined];
        if (parsed) month = [greg component:NSCalendarUnitMonth fromDate:parsed];
    }
    if (month < 1 || month > 12) return NO;
    NSDateComponents *now = [greg components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:date];
    NSInteger joinedIdx = year * 12 + (month - 1);
    NSInteger nowIdx = now.year * 12 + (now.month - 1);
    return nowIdx - joinedIdx <= 2 && nowIdx - joinedIdx >= 0;
}

+ (BOOL)isNewAccount:(NSString *)joined { return TPIsNewAccountAtDate(joined, [NSDate date]); }

#pragma mark - Pointer safety

static CFMutableSetRef gClassSet;

static void TPBuildClassSet(void) {
    if (gClassSet) return;
    CFMutableSetRef set = CFSetCreateMutable(NULL, 0, NULL);
    typedef Class __unsafe_unretained *(*TPCopyClasses)(unsigned int *);
    static TPCopyClasses copyClasses;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ copyClasses = (TPCopyClasses)dlsym(RTLD_DEFAULT, "objc_copyRealizedClassList"); });
    if (copyClasses) {
        unsigned int n = 0;
        Class __unsafe_unretained *list = copyClasses(&n);
        for (unsigned int i = 0; i < n; i++) CFSetAddValue(set, (__bridge const void *)list[i]);
        free(list);
    }
    gClassSet = set;
}

// Block arguments of unknown signature are received as raw pointers; only treat one as an object
// when it is a tagged pointer or a heap allocation whose isa is a known class.
static id TPAsObject(void *p) {
    uintptr_t v = (uintptr_t)p;
    if (!v) return nil;
    if ((intptr_t)v < 0) return (__bridge id)p;
    if (v < 0x100000000ULL || (v & 7)) return nil;
    if (malloc_size(p) < 16) return nil;
    uintptr_t isa = *(uintptr_t *)p;
    const uintptr_t masks[] = { 0x0000000ffffffff8ULL, 0x007ffffffffffff8ULL, ~(uintptr_t)7 };
    for (int i = 0; i < 3; i++) {
        if (gClassSet && CFSetContainsValue(gClassSet, (const void *)(isa & masks[i]))) return (__bridge id)p;
    }
    return nil;
}

#pragma mark - String harvesting

static BOOL TPSkipClass(id obj) {
    NSString *n = NSStringFromClass([obj class]);
    for (NSString *p in @[@"UI", @"CA", @"BKObjectSet", @"BKContext", @"IGUserSession", @"FBMobileConfig", @"NSMapTable", @"NSHashTable", @"NSBundle", @"NSUserDefaults"]) {
        if ([n hasPrefix:p]) return YES;
    }
    return NO;
}

static void TPHarvestStrings(id obj, int depth, NSMutableSet<NSValue *> *visited, NSMutableArray<NSString *> *out, int *budget) {
    if (!obj || depth > 400 || *budget <= 0) return;
    (*budget)--;
    if ([obj isKindOfClass:[NSString class]]) { if ([(NSString *)obj length]) [out addObject:obj]; return; }
    if ([obj isKindOfClass:[NSAttributedString class]]) { [out addObject:[(NSAttributedString *)obj string]]; return; }
    if ([obj isKindOfClass:[NSData class]]) {
        NSData *d = obj;
        if (d.length > 2 && d.length < 4000000) {
            NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if ([s hasPrefix:@"for (;;);"]) s = [s substringFromIndex:9];
            id json = s ? [NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
            if (json) TPHarvestStrings(json, depth + 1, visited, out, budget);
            else if (s.length) [out addObject:s];
        }
        return;
    }
    if ([obj isKindOfClass:[NSNumber class]]) { [out addObject:[@"\u241Fnum:" stringByAppendingString:[obj stringValue]]]; return; }
    if ([obj isKindOfClass:[NSDate class]] || [obj isKindOfClass:[NSURL class]]) return;
    if ([obj isKindOfClass:[UIResponder class]] || [obj isKindOfClass:[CALayer class]] || [obj isKindOfClass:[UIImage class]]) return;
    if ([obj isKindOfClass:[NSError class]]) {
        NSError *e = obj;
        [out addObject:[NSString stringWithFormat:@"NSError %@ %ld", e.domain, (long)e.code]];
        if (e.localizedDescription) [out addObject:e.localizedDescription];
        TPHarvestStrings(e.userInfo, depth + 1, visited, out, budget);
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        if (d[@"text"] || d[@"text_style"] || d[@"on_bind"]) {
            id style = d[@"text_style"];
            if ([style isKindOfClass:[NSString class]]) [out addObject:[@"␟style:" stringByAppendingString:style]];
        }
        for (id k in d) TPHarvestStrings(d[k], depth + 1, visited, out, budget);
        return;
    }
    if ([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSOrderedSet class]] || [obj isKindOfClass:[NSSet class]]) {
        for (id v in obj) TPHarvestStrings(v, depth + 1, visited, out, budget);
        return;
    }
    if (TPSkipClass(obj) || depth > 14) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)obj];
    if ([visited containsObject:key]) return;
    [visited addObject:key];
    for (Class c = object_getClass(obj); c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *ivars = class_copyIvarList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            const char *enc = ivar_getTypeEncoding(ivars[i]);
            if (!enc || enc[0] != '@' || enc[1] == '?') continue;
            id v = object_getIvar(obj, ivars[i]);
            TPHarvestStrings(v, depth + 1, visited, out, budget);
        }
        free(ivars);
    }
}

static NSString *TPDecodeEscapes(NSString *s) {
    if (![s containsString:@"\\u"]) return s;
    NSString *wrapped = [NSString stringWithFormat:@"\"%@\"", [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    id v = [NSJSONSerialization JSONObjectWithData:[wrapped dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil];
    return [v isKindOfClass:[NSString class]] ? v : s;
}

// Bloks hides the location in a conditional binding: (bk.action.core.If, cond, "Taiwan", "Not shared")
static NSString *TPValueFromBinding(NSString *s) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\"((?:[^\"\\\\]|\\\\.)*)\"\\s*,\\s*\"((?:[^\"\\\\]|\\\\.)+)\"" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return nil;
    NSString *a = TPDecodeEscapes([s substringWithRange:[m rangeAtIndex:1]]);
    NSString *b = TPDecodeEscapes([s substringWithRange:[m rangeAtIndex:2]]);
    return a.length ? a : b;
}

static NSArray<NSString *> *kJoinedLabels, *kLocationLabels, *kSkipLabels;

static void TPInitLabels(void) {
    if (kJoinedLabels) return;
    kJoinedLabels   = @[@"Joined", @"Date joined", @"已加入", @"加入日期", @"加入時間", @"加入时间", @"参加日", @"가입일", @"가입 날짜", @"Se unió", @"Inscrit(e)"];
    kLocationLabels = @[@"Based in", @"所在地點", @"所在地", @"所在地区", @"위치", @"거주지", @"Ubicación"];
    kSkipLabels     = @[@"Name", @"名稱", @"名称", @"名前", @"이름",
                        @"Former usernames", @"Previous usernames", @"先前的用戶名稱", @"先前的使用者名稱", @"先前的用户名称", @"以前のユーザーネーム", @"이전 사용자 이름",
                        @"Verified by Meta", @"Meta 驗證", @"Meta 验证", @"Metaにより認証", @"Metaにより認証済み", @"Meta認証", @"Meta 인증", @"Meta 인증 완료"];
}

static BOOL TPIsLabel(NSString *s) {
    return [kJoinedLabels containsObject:s] || [kLocationLabels containsObject:s] || [kSkipLabels containsObject:s];
}

static NSString *TPCleanValue(NSString *raw) {
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([s hasPrefix:@"("] && [s containsString:@"\""]) s = TPValueFromBinding(s);
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length || s.length > 80 || [s hasPrefix:@"␟"] || [s hasPrefix:@"http"] || TPIsLabel(s)) return nil;
    return s;
}

// The native response is a Bloks action bundle whose state entries look like
//   <id> | gs | THREADS_ABOUT_THIS_PROFILE:<name> | p | <value>
// Collect name -> value; a value that is really the next entry's id (followed by "gs") is absent.
static NSDictionary<NSString *, NSString *> *TPStateValues(NSArray<NSString *> *strings) {
    static NSString *const prefix = @"THREADS_ABOUT_THIS_PROFILE:";
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < strings.count; i++) {
        NSString *k = strings[i];
        if (![k hasPrefix:prefix]) continue;
        NSString *name = [k substringFromIndex:prefix.length];
        NSUInteger j = i + 1;
        if (j < strings.count && [strings[j] isEqualToString:@"p"]) j++;
        if (j >= strings.count) continue;
        NSString *v = strings[j];
        if (j + 1 < strings.count && [strings[j + 1] isEqualToString:@"gs"]) continue;
        if ([v hasPrefix:prefix]) continue;
        if ([v hasPrefix:@"␟num:"]) v = [v substringFromIndex:5];
        if (v.length && !m[name]) m[name] = v;
    }
    return m;
}

static BOOL TPLooksLikeMonth(NSString *v) {
    // A join date such as "2023年7月", "July 2023" or "2023년 7월": a plausible year that isn't part
    // of a colour (#FF000000), number or id.
    if (!v.length || v.length > 40 || [v hasPrefix:@"#"] || [v hasPrefix:@"("] || [v hasPrefix:@"http"]) return NO;
    return [v rangeOfString:@"(?<![0-9A-Za-z])(19|20)\\d{2}(?![0-9A-Za-z])" options:NSRegularExpressionSearch].length > 0;
}

static NSString *TPJoinOrdinal(NSString *value) {
    NSString *s = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length || s.length > 24) return nil;
    if ([s rangeOfString:@"^(?:[#＃][0-9]+(?:[,，.\u00a0\u202f ][0-9]{3})*|[0-9]+(?:[.,][0-9]+)?\\s*[KMBkmb萬万億亿]\\s*[+＋])$" options:NSRegularExpressionSearch].location != NSNotFound)
        return s;
    return nil;
}

static NSDictionary *TPJoinText(NSString *value) {
    NSRange dot = [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"·•"]];
    NSString *month = dot.location == NSNotFound ? value : [value substringToIndex:dot.location];
    month = [month stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!TPLooksLikeMonth(month)) return nil;
    NSString *number = dot.location == NSNotFound ? nil : TPJoinOrdinal([value substringFromIndex:NSMaxRange(dot)]);
    return number ? @{@"joined": month, @"number": number} : @{@"joined": month};
}

static NSString *TPMonthFromTimestamp(double t) {
    if (t > 1e12) t /= 1000;
    if (t < 1.0e9 || t > 4.0e9) return nil;
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = NSLocale.currentLocale;
    f.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    f.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yMMMM" options:0 locale:f.locale];
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

static NSDictionary *TPJoinInfoForUser(id user) {
    if (!user) return nil;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    SEL joinedSelector = NSSelectorFromString(@"textPostAppJoinedTime");
    id joined = [user respondsToSelector:joinedSelector] ? ((id (*)(id, SEL))objc_msgSend)(user, joinedSelector) : nil;
    if ([joined respondsToSelector:@selector(integerValue)]) {
        NSString *month = TPMonthFromTimestamp((double)[joined integerValue]);
        if (month) info[@"joined"] = month;
    }
    SEL labelSelector = NSSelectorFromString(@"textPostAppJoinerNumberLabel");
    id label = [user respondsToSelector:labelSelector] ? ((id (*)(id, SEL))objc_msgSend)(user, labelSelector) : nil;
    if ([label isKindOfClass:NSString.class] && [label length] && [label length] <= 24) info[@"number"] = label;
    if (!info[@"number"]) {
        SEL numberSelector = NSSelectorFromString(@"textPostAppJoinerNumber");
        id number = [user respondsToSelector:numberSelector] ? ((id (*)(id, SEL))objc_msgSend)(user, numberSelector) : nil;
        if ([number respondsToSelector:@selector(integerValue)] && [number integerValue] > 0) {
            NSNumberFormatter *f = [NSNumberFormatter new];
            f.numberStyle = NSNumberFormatterDecimalStyle;
            f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            f.usesGroupingSeparator = YES;
            f.groupingSize = 3;
            info[@"number"] = [@"#" stringByAppendingString:[f stringFromNumber:@([number integerValue])]];
        }
    }
    return info.count ? info : nil;
}

static NSDictionary *TPParseState(NSDictionary<NSString *, NSString *> *st) {
    NSString *location = nil;
    NSDictionary *join = nil;
    BOOL countryHidden = [st[@"about_this_profile_country_visibility"] isEqualToString:@"0"];
    for (NSString *name in st) {
        NSString *v = st[name], *n = name.lowercaseString;
        if (countryHidden) break;
        if ([n hasSuffix:@"_visibility"] || [n containsString:@"visib"]) continue;
        if (!location && ([n hasSuffix:@"country"] || [n hasSuffix:@"location"] || [n hasSuffix:@"based_in"]) && !TPLooksLikeMonth(v)) location = v;
    }
    for (NSString *name in st) {
        NSString *v = st[name], *n = name.lowercaseString;
        if (!([n containsString:@"join"] || [n containsString:@"date"] || [n containsString:@"creat"])) continue;
        if ([n containsString:@"number"] || [n containsString:@"ordinal"]) continue;
        join = TPJoinText(v);
        if (join) break;
        if ([v rangeOfString:@"^[0-9]{10}(?:[0-9]{3})?$" options:NSRegularExpressionSearch].location != NSNotFound) {
            NSString *month = TPMonthFromTimestamp(v.doubleValue);
            if (month) { join = @{@"joined": month}; break; }
        }
    }
    if (!join) for (NSString *name in st) {
        if ([name.lowercaseString containsString:@"number"] || [name.lowercaseString containsString:@"ordinal"]) continue;
        join = TPJoinText(st[name]);
        if (join) break;
    }
    NSMutableDictionary *r = [join mutableCopy] ?: [NSMutableDictionary dictionary];
    if (location.length) r[@"location"] = location;
    return r;
}

static NSDictionary *TPParseStrings(NSArray<NSString *> *strings) {
    TPInitLabels();
    NSDictionary *st = TPStateValues(strings);
    NSDictionary *fromState = st.count ? TPParseState(st) : nil;
    NSString *location = nil, *joined = nil, *number = nil, *username = nil, *fullName = nil;
    // "Name" row: "Display Name（@handle" (the closing bracket is a separate span) or just "handle".
    for (NSUInteger i = 0; i < strings.count && !username; i++) {
        NSString *s = [strings[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![@[@"Name", @"名稱", @"名称", @"名前", @"이름"] containsObject:s]) continue;
        for (NSUInteger j = i + 1; j < strings.count && j <= i + 12; j++) {
            NSString *v = [strings[j] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSRange at = [v rangeOfString:@"@"];
            if (at.location != NSNotFound) {
                NSString *h = [v substringFromIndex:at.location + 1];
                NSRange bad = [h rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"].invertedSet];
                if (bad.location != NSNotFound) h = [h substringToIndex:bad.location];
                if (h.length) {
                    username = h;
                    NSString *n = [[v substringToIndex:at.location] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" （("]];
                    if (n.length) fullName = n;
                }
                break;
            }
            if ([v rangeOfString:@"^[A-Za-z0-9._]{2,30}$" options:NSRegularExpressionSearch].location != NSNotFound &&
                ![v hasSuffix:@"dp"] && ![v hasSuffix:@"sp"] && ![@[@"normal", @"semibold", @"bold", @"column", @"row", @"center"] containsObject:v]) {
                username = v;
                break;
            }
        }
    }
    for (NSUInteger i = 0; i < strings.count; i++) {
        NSString *s = [strings[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL isJoined = [kJoinedLabels containsObject:s];
        BOOL isLocation = [kLocationLabels containsObject:s];
        if (!isJoined && !isLocation) continue;
        for (NSUInteger j = i + 1; j < strings.count && j <= i + 40; j++) {
            NSString *t = [strings[j] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (TPIsLabel(t)) break;
            NSString *v = TPCleanValue(t);
            if (!v) continue;
            NSDictionary *rowJoin = isJoined ? TPJoinText(v) : nil;
            if (isJoined && !rowJoin) continue;
            if (isLocation && ([v hasSuffix:@"dp"] || [v hasSuffix:@"sp"] || [v hasPrefix:@"#"] || [v hasPrefix:@"("] ||
                               [@[@"column", @"row", @"visible", @"gone", @"semibold", @"normal", @"bold", @"center", @"start", @"end"] containsObject:v])) continue;
            if (isJoined && !joined) {
                joined = rowJoin[@"joined"];
                number = rowJoin[@"number"];
                BOOL separator = NO;
                for (NSUInteger k = j + 1; !number && k < strings.count && k <= j + 6; k++) {
                    NSString *span = [strings[k] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if ([span hasPrefix:@"␟style:"]) continue;
                    if ([span isEqualToString:@"·"] || [span isEqualToString:@"•"]) { separator = YES; continue; }
                    if (separator) number = TPJoinOrdinal(span);
                    break;
                }
            } else if (isLocation && !location) {
                location = v;
            }
            break;
        }
    }
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    if (location) r[@"location"] = location;
    if (joined) r[@"joined"] = joined;
    if (number.length && number.length <= 24) r[@"number"] = number;
    if (username.length) r[@"u"] = username;
    if (fullName.length && fullName.length <= 60) r[@"n"] = fullName;
    if (fromState[@"location"]) r[@"location"] = fromState[@"location"];
    if (!joined && fromState[@"joined"]) r[@"joined"] = fromState[@"joined"];
    if (!number && [r[@"joined"] isEqualToString:fromState[@"joined"]] && fromState[@"number"]) r[@"number"] = fromState[@"number"];
    if ([st[@"about_this_profile_country_visibility"] isEqualToString:@"0"] ||
        [@[@"未分享", @"Not shared", @"未分享地點", @"共有されていません", @"공유되지 않음"] containsObject:r[@"location"] ?: @""]) {
        [r removeObjectForKey:@"location"];
        r[@"hidden"] = @YES;
    }
    return r;
}

static BOOL TPLooksRateLimited(NSArray<NSString *> *strings, BOOL success) {
    for (NSString *s in strings) {
        NSString *l = s.lowercaseString;
        if ([l containsString:@"feedback_required"] || [l containsString:@"rate limit"] || [l containsString:@"ratelimit"] ||
            [l containsString:@"too many requests"] || [l containsString:@"please wait a few minutes"]) return YES;
        if (success) continue;
        if ([l containsString:@"spam"] || [l containsString:@"try again later"] || [l containsString:@"checkpoint"] ||
            ([l hasPrefix:@"nserror "] && [l hasSuffix:@" 429"])) return YES;
    }
    return NO;
}

#pragma mark - Queue

+ (void)requestPk:(NSString *)pk {
    if (!pk.length || ![self enabled]) return;
    TPLoadCache();
    if ([self infoForPk:pk] || [gPending containsObject:pk] || [pk isEqualToString:gInFlightPk]) return;
    if ([self pausedRemaining] > 0 || gParserGaveUp || gSessionCount >= kSessionMax) return;
    [gQueue addObject:pk];
    [gPending addObject:pk];
    while (gQueue.count > kQueueMax) { [gPending removeObject:gQueue.firstObject]; [gQueue removeObjectAtIndex:0]; }
    if (!gPumpScheduled) [self pump];
}

static void TPPauseForRateLimit(NSString *why) {
    NSTimeInterval until = [NSDate date].timeIntervalSince1970 + kCooldown;
    [[TPPrefs defaults] setDouble:until forKey:kPausedKey];
    [gQueue removeAllObjects];
    [gPending removeAllObjects];
    [TPAuthorInfo log:[@"PAUSED 1h: " stringByAppendingString:why ?: @"?"]];
    [TPHUD toast:TPL(@"Threads asked to slow down. Author info paused for 1 hour.")];
}

static NSDictionary *TPParams(NSString *pk, NSInteger variant) {
    NSDictionary *inner = @{ @"target_user_id": pk,
                             @"referer_type": @"TextPostAppProfileOverflow",
                             @"atpTriggerSessionID": NSUUID.UUID.UUIDString.lowercaseString };
    if (variant == 0) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:inner options:0 error:nil];
        return @{ @"params": [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] };
    }
    return inner;
}

// The built object set failed (no response or an error, often a bad connection). Try again a few
// times with growing pauses before falling back to asking for "About this profile".
static void TPSyntheticRetryOrGiveUp(void) {
    static const NSTimeInterval waits[] = { 30, 60, 120 };
    if (gSyntheticRetries >= 3) { gSyntheticFailed = YES; return; }
    NSTimeInterval w = waits[gSyntheticRetries++];
    gSyntheticFailed = YES;   // hold off until the retry
    [TPAuthorInfo log:[NSString stringWithFormat:@"built objectSet: retrying in %.0fs", w]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(w * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gObjectSet) return;
        gSyntheticFailed = NO;
        [TPAuthorInfo pump];
    });
}

// Asks the user to open "About this profile" once. An alert rather than a toast, so it can't be
// missed; at most once a day.
static void TPShowSeedHint(void) {
    NSUserDefaults *d = [TPPrefs defaults];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - [d doubleForKey:@"tp_author_hint_at"] < 86400) return;
    UIViewController *top = [TPDownloader topViewController];
    if (!top || top.presentedViewController || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        gHintShown = NO;   // try again on a later pump
        return;
    }
    [d setDouble:now forKey:@"tp_author_hint_at"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:TPL(@"Author Info")
        message:TPL(@"Open anyone's \"About this profile\" once to start showing author info.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:TPL(@"Close") style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

static void TPSyntheticTimedOut(void) {
    if (!(gSyntheticSet && !gObjectSet)) return;
    [[TPPrefs defaults] removeObjectForKey:kSynthPending];
    [[TPPrefs defaults] setObject:@"timeout" forKey:@"tp_author_synth_last"];
    gSyntheticSet = nil;
    [TPAuthorInfo log:@"built objectSet: no response"];
    TPSyntheticRetryOrGiveUp();
}

static void TPRequeueVisible(void);

static void TPFinish(NSUInteger token) {
    if (token != gToken || !gInFlight) return;
    gInFlight = NO;
    gInFlightPk = nil;
    if (!gQueue.count) TPRequeueVisible();
    [TPAuthorInfo pump];
}

static void TPHandleResult(NSUInteger token, NSString *pk, NSInteger variant, BOOL success, NSArray *objs, NSString *shape, NSDictionary *nativeJoin) {
    if (token != gToken || !gInFlight) return;
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    NSMutableSet *visited = [NSMutableSet set];
    int budget = 6000;
    for (id o in objs) TPHarvestStrings(o, 0, visited, strings, &budget);
    if (strings.count < 3) {
        for (id o in objs) {
            NSString *d = nil;
            @try { d = [o description]; } @catch (__unused NSException *e) {}
            if (d.length) [strings addObject:d];
        }
    }
    [TPAuthorInfo log:[NSString stringWithFormat:@"%@ pk=%@ v%ld args(%@) strings=%lu", success ? @"OK" : @"ERR", pk, (long)variant, shape, (unsigned long)strings.count]];

    if (TPLooksRateLimited(strings, success)) {
        TPPauseForRateLimit([strings componentsJoinedByString:@" | "].length > 160
                            ? [[strings componentsJoinedByString:@" | "] substringToIndex:160]
                            : [strings componentsJoinedByString:@" | "]);
        TPFinish(token);
        return;
    }

    NSString *joinedAll = [strings componentsJoinedByString:@" | "];
    BOOL usedSynthetic = gSyntheticSet && !gObjectSet;
    if (usedSynthetic) [[TPPrefs defaults] removeObjectForKey:kSynthPending];
    if (usedSynthetic && success) {
        static BOOL logged;
        if (!logged) { logged = YES; [TPAuthorInfo log:[NSString stringWithFormat:@"  built objectSet works (subtype %ld)", (long)gSyntheticSubtype]]; }
        gObjectSet = gSyntheticSet;
        gObjectSetSource = @"Built";
        [[TPPrefs defaults] setObject:[NSString stringWithFormat:@"ok (subtype %ld)", (long)gSyntheticSubtype] forKey:@"tp_author_synth_last"];
        [[TPPrefs defaults] setBool:YES forKey:@"tp_author_synth_worked"];
    } else if (usedSynthetic) {
        [[TPPrefs defaults] setObject:@"error" forKey:@"tp_author_synth_last"];
        [TPAuthorInfo log:[@"  built objectSet failed: " stringByAppendingString:joinedAll.length > 200 ? [joinedAll substringToIndex:200] : joinedAll]];
        gSyntheticSet = nil;
        if (gSyntheticSubtype < 2 && [joinedAll.lowercaseString containsString:@"no session context"]) gSyntheticSubtype++;
        else TPSyntheticRetryOrGiveUp();
        [gQueue addObject:pk];
        [gPending addObject:pk];
        gInFlight = NO;
        gInFlightPk = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [TPAuthorInfo pump]; });
        return;
    }
    if (!success && [joinedAll.lowercaseString containsString:@"no session context"]) {
        [TPAuthorInfo log:@"  objectSet has no session; waiting for another"];
        if (!gBadObjectSets) gBadObjectSets = [NSHashTable weakObjectsHashTable];
        if (gObjectSet) [gBadObjectSets addObject:gObjectSet];
        gObjectSet = nil;
        gObjectSetSource = nil;
        [gQueue addObject:pk];
        [gPending addObject:pk];
        gInFlight = NO;
        gInFlightPk = nil;
        return; // noteObjectSet: pumps again
    }

    NSDictionary *st = success ? TPStateValues(strings) : nil;
    if (st.count) {
        NSMutableArray *kv = [NSMutableArray array];
        for (NSString *k in [st.allKeys sortedArrayUsingSelector:@selector(compare:)]) [kv addObject:[NSString stringWithFormat:@"%@=%@", k, st[k]]];
        [TPAuthorInfo log:[@"  state: " stringByAppendingString:[kv componentsJoinedByString:@", "]]];
    }
    NSMutableDictionary *info = success ? [TPParseStrings(strings) mutableCopy] : [NSMutableDictionary dictionary];
    if (!info[@"joined"] && nativeJoin[@"joined"]) info[@"joined"] = nativeJoin[@"joined"];
    if (!info[@"number"] && nativeJoin[@"number"]) info[@"number"] = nativeJoin[@"number"];
    if (TPHasAuthorDetails(info)) {
        gEmptyStreak = 0;
        gSuccessCount++;
        [[TPPrefs defaults] setInteger:variant forKey:kVariantKey];
        [TPAuthorInfo log:[NSString stringWithFormat:@"  -> %@ / %@ / %@", info[@"location"] ?: @"-", info[@"joined"] ?: @"-", info[@"number"] ?: @"-"]];
        TPStore(pk, info[@"location"], info[@"joined"], info[@"number"], [info[@"hidden"] boolValue], !success, info);
    } else {
        gEmptyStreak++;
        NSString *sample = [strings componentsJoinedByString:@" | "];
        if (sample.length > 600) sample = [sample substringToIndex:600];
        [TPAuthorInfo log:[@"  strings: " stringByAppendingString:sample]];
        TPStore(pk, nil, nil, nil, NO, !success, nil);
        if (!success && !gSuccessCount && gEmptyStreak >= 6) {
            gParserGaveUp = YES;
            [gQueue removeAllObjects];
            [gPending removeAllObjects];
            [TPAuthorInfo log:@"no usable responses; stopped for this launch"];
        }
    }
    TPFinish(token);
}

+ (void)pump {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self pump]; }); return; }
    if (gInFlight || !gQueue.count || ![self enabled]) return;
    if ([self pausedRemaining] > 0 || gParserGaveUp || gSessionCount >= kSessionMax) {
        [gQueue removeAllObjects]; [gPending removeAllObjects];
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSTimeInterval delay = TPIsThreads410() ? kLegacyDelay : kDelay;
    if (now - gLastRequest < delay) {
        if (gPumpScheduled) return;
        gPumpScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay - (now - gLastRequest) + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gPumpScheduled = NO;
            [self pump];
        });
        return;
    }

    id os = gObjectSet;
    if (!os && !gSyntheticFailed && gUserSession && gPandoService && ![[TPPrefs defaults] boolForKey:kSynthDisabled]) {
        if (gSyntheticSubtype < 0) gSyntheticSubtype = 0;
        if (!gSyntheticSet) gSyntheticSet = TPBuildObjectSet(gSyntheticSubtype);
        os = gSyntheticSet;
        if (os) {
            [[TPPrefs defaults] setBool:YES forKey:kSynthPending];
            [[TPPrefs defaults] synchronize];
            [self log:[NSString stringWithFormat:@"trying built objectSet (subtype %ld)", (long)gSyntheticSubtype]];
        } else {
            gSyntheticFailed = YES;
            [self log:@"could not build objectSet"];
        }
    }
    if (!os) {
        static BOOL logged;
        if (!logged) { logged = YES; [self log:gUserSession ? @"waiting: no objectSet captured yet" : @"waiting: no objectSet, no user session"]; }
        BOOL gaveUp = (gSyntheticFailed && gSyntheticRetries >= 3) || [[TPPrefs defaults] boolForKey:kSynthDisabled];
        if (!gHintShown && gaveUp) {
            gHintShown = YES;
            TPShowSeedHint();
        }
        return; // noteObjectSet: pumps again
    }

    Class F = objc_getClass("BKSharedAsyncActionDataFetcher");
    SEL sel = NSSelectorFromString(@"fetchWithObjectSet:appID:params:timeoutOverride:successHandler:errorHandler:callbackQueue:");
    BOOL useLegacyRoot = NO;
    if (!F || ![F respondsToSelector:sel]) {
        F = objc_getClass("BKDataFetchGraphQL");
        sel = NSSelectorFromString(@"fetchRootAppWithObjectSet:appID:params:purpose:cacheTTL:successHandler:errorHandler:callbackQueue:");
        useLegacyRoot = F && [F respondsToSelector:sel];
    }
    if (!F || ![F respondsToSelector:sel]) {
        static BOOL logged;
        if (!logged) { logged = YES; [self log:@"BKSharedAsyncActionDataFetcher not available"]; }
        gParserGaveUp = YES;
        return;
    }

    NSString *pk = gQueue.lastObject;   // newest first: whatever is on screen now
    [gQueue removeLastObject];
    [gPending removeObject:pk];
    if ([self infoForPk:pk]) { [self pump]; return; }
    // Scrolled away while waiting: don't spend a request (and the 1.5 s gap) on it. If it comes
    // back on screen it is queued again.
    if (!TPPkOnScreen(pk)) { TPRequeueVisible(); [self pump]; return; }

    gInFlight = YES;
    gInFlightPk = pk;
    gLastRequest = now;
    NSUInteger token = ++gToken;
    NSInteger variant = [[TPPrefs defaults] integerForKey:kVariantKey];
    gSessionCount++;
    NSDictionary *params = useLegacyRoot
        ? @{ @"target_user_id": @(pk.longLongValue), @"referer_type": @"TextPostAppProfileOverflow" }
        : TPParams(pk, variant);
    NSDictionary *nativeJoin = TPIsThreads410() ? TPHeaderJoinInfo(pk) : nil;

    void (^ok)(id, id) = ^(id result, id status) {
        NSArray *objs = result ? @[result] : @[];
        NSString *shape = [NSString stringWithFormat:@"%@, %@", result ? NSStringFromClass([result class]) : @"nil", status ? NSStringFromClass([status class]) : @"nil"];
        dispatch_async(dispatch_get_main_queue(), ^{ TPHandleResult(token, pk, variant, YES, objs, shape, nativeJoin); });
    };
    void (^fail)(id) = ^(id error) {
        NSArray *objs = error ? @[error] : @[];
        NSString *shape = error ? NSStringFromClass([error class]) : @"nil";
        dispatch_async(dispatch_get_main_queue(), ^{ TPHandleResult(token, pk, variant, NO, objs, shape, nativeJoin); });
    };

    @try {
        gSelfCall = YES;
        if (useLegacyRoot) {
            // 410's bottom sheet is a root-app query; its callback returns the parsed bundle JSON.
            ((void (*)(id, SEL, id, id, id, long long, unsigned long long, id, id, id))objc_msgSend)(F, sel, os, kLegacyAppID, params, 1, 3600, ok, fail, dispatch_get_main_queue());
        } else {
            ((void (*)(id, SEL, id, id, id, id, id, id, id))objc_msgSend)(F, sel, os, kAppID, params, nil, ok, fail, dispatch_get_main_queue());
        }
        gSelfCall = NO;
    } @catch (NSException *e) {
        gSelfCall = NO;
        [self log:[@"fetch threw: " stringByAppendingString:e.reason ?: @"?"]];
        gInFlight = NO; gInFlightPk = nil;
        gParserGaveUp = YES;
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token == gToken && gInFlight) {
            TPSyntheticTimedOut();
            [self log:[@"timeout pk=" stringByAppendingString:pk]];
            TPStore(pk, nil, nil, nil, NO, YES, nil);
            TPFinish(token);
        }
    });
}

#pragma mark - Swift String reading

// Reads a Swift `String?` stored inline in an object (two words). Handles small, native and
// bridged representations; anything else returns nil.
static NSString *TPSwiftString(const void *base) {
    uint64_t w0 = ((const uint64_t *)base)[0], w1 = ((const uint64_t *)base)[1];
    if (!w0 && !w1) return nil;
    uint8_t disc = (uint8_t)(w1 >> 56);
    if (disc & 0x20) {
        NSUInteger n = disc & 0x0F;
        if (!n || n > 15) return nil;
        char buf[16];
        memcpy(buf, &w0, 8);
        memcpy(buf + 8, &w1, 7);
        return [[NSString alloc] initWithBytes:buf length:n encoding:NSUTF8StringEncoding];
    }
    uintptr_t obj = (uintptr_t)(w1 & 0x0FFFFFFFFFFFFFFFULL);
    if (obj < 0x100000000ULL) return nil;
    if (disc & 0x40) { // bridged NSString
        TPBuildClassSet();
        id o = TPAsObject((void *)obj);
        return [o isKindOfClass:[NSString class]] ? [o copy] : nil;
    }
    uint64_t count = w0 & 0x0000FFFFFFFFFFFFULL;
    if (!count || count > 64) return nil;
    if (!(disc & 0x80) && malloc_size((void *)obj) == 0) return nil; // native heap storage
    return [[NSString alloc] initWithBytes:(const void *)(obj + 32) length:(NSUInteger)count encoding:NSUTF8StringEncoding];
}

static BOOL TPIsDigits(NSString *s) {
    if (!s.length || s.length > 24) return NO;
    return [s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

static id TPIvarObject(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    return object_getIvar(obj, iv);
}

static NSString *TPHeaderPk(UIView *contentView) {
    id viewModel = TPIvarObject(contentView, "viewModel");
    id user = viewModel ? TPIvarObject(viewModel, "user") : nil;
    SEL pkSelector = NSSelectorFromString(@"pk");
    id value = [user respondsToSelector:pkSelector] ? ((id (*)(id, SEL))objc_msgSend)(user, pkSelector) : nil;
    if ([value isKindOfClass:[NSString class]] && TPIsDigits(value)) return value;
    id pic = TPIvarObject(contentView, "profilePictureView");
    NSString *pk = nil;
    if (pic) {
        Ivar iv = class_getInstanceVariable(object_getClass(pic), "userPk");
        if (iv) pk = TPSwiftString((const char *)(__bridge void *)pic + ivar_getOffset(iv));
    }
    return TPIsDigits(pk) ? pk : nil;
}

+ (NSString *)pkForHeader:(UIView *)contentView { return TPHeaderPk(contentView); }

#pragma mark - Badge

// The header's title is the author's handle. Some About-this-profile layouts have no Name row, so
// the handle seen here fills the gap (Location Stats needs it to open the profile).
static NSAttributedString *TPTitleText(UIView *v, int depth) {
    if (!v || depth > 4) return nil;
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)v;
        return label.attributedText ?: [[NSAttributedString alloc] initWithString:label.text ?: @"" attributes:@{ NSFontAttributeName: label.font }];
    }
    if ([v respondsToSelector:@selector(attributedText)]) {
        id t = [(id)v attributedText];
        if ([t isKindOfClass:[NSAttributedString class]]) return t;
    }
    for (UIView *s in v.subviews) { NSAttributedString *t = TPTitleText(s, depth + 1); if (t.length) return t; }
    return nil;
}

static void TPNoteHeaderName(NSString *pk, UIView *title) {
    if (!pk.length) return;
    NSString *t = [TPTitleText(title, 0).string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // The title can carry a verified mark or other trailing text; keep the leading handle.
    NSRange r = [t ?: @"" rangeOfString:@"^[A-Za-z0-9._]{1,30}" options:NSRegularExpressionSearch];
    if (r.location == NSNotFound) return;
    NSString *u = [t substringWithRange:r];
    if (!gHeaderNames) gHeaderNames = [NSMutableDictionary dictionary];
    if ([gHeaderNames[pk] isEqualToString:u]) return;
    gHeaderNames[pk] = u;
    NSDictionary *e = gCache[pk];
    if (e && ![e[@"u"] length]) {
        NSMutableDictionary *m = [e mutableCopy];
        m[@"u"] = u;
        gCache[pk] = m;
        TPSaveCacheSoon();
    }
}

static const void *kBadgeKey = &kBadgeKey;
static NSHashTable *gBadges;

static void TPInvalidateAuthorHeader(UIView *host) {
    if (!host.window) return;
    UIView *v = host;
    while (v && ![v isKindOfClass:UICollectionViewCell.class]) v = v.superview;
    UICollectionViewCell *cell = (UICollectionViewCell *)v;
    while (v && ![v isKindOfClass:UICollectionView.class]) v = v.superview;
    UICollectionView *cv = (UICollectionView *)v;
    NSIndexPath *path = cell ? [cv indexPathForCell:cell] : nil;
    if (!path) return;
    for (id adapter in @[cv.dataSource ?: (id)NSNull.null, cv.delegate ?: (id)NSNull.null]) {
        SEL section = NSSelectorFromString(@"sectionControllerForSection:");
        if (![adapter respondsToSelector:section]) continue;
        id sc = ((id (*)(id, SEL, NSInteger))objc_msgSend)(adapter, section, path.section);
        SEL collection = NSSelectorFromString(@"collectionContext");
        id context = [sc respondsToSelector:collection] ? ((id (*)(id, SEL))objc_msgSend)(sc, collection) : nil;
        SEL invalidate = NSSelectorFromString(@"invalidateLayoutForSectionController:completion:");
        if ([context respondsToSelector:invalidate])
            ((void (*)(id, SEL, id, id))objc_msgSend)(context, invalidate, sc, nil);
        break;
    }
}

// Headers that scrolled in while the queue was full were dropped; once it drains, pick up
// whatever is still on screen without info.
static BOOL TPHeaderVisible(UIView *host) {
    UIWindow *window = host.window;
    if (!window || host.hidden || host.alpha < 0.05) return NO;
    CGRect visible = window.bounds;
    for (UIView *v = host.superview; v && v != window; v = v.superview) {
        if (v.hidden || v.alpha < 0.05) return NO;
        if (v.clipsToBounds) visible = CGRectIntersection(visible, [v convertRect:v.bounds toView:window]);
    }
    CGRect frame = [host convertRect:host.bounds toView:window];
    return !CGRectIsEmpty(frame) && CGRectIntersectsRect(visible, frame);
}

static BOOL TPPkOnScreen(NSString *pk) {
    for (TPAuthorBadgeLabel *b in gBadges.allObjects) {
        if (![b.pk isEqualToString:pk]) continue;
        if (TPHeaderVisible(b.host)) return YES;
    }
    return NO;
}

static NSDictionary *TPHeaderJoinInfo(NSString *pk) {
    for (TPAuthorBadgeLabel *badge in gBadges.allObjects) {
        UIView *host = badge.host;
        if (![badge.pk isEqualToString:pk]) continue;
        id model = TPIvarObject(host, "viewModel");
        id user = TPIvarObject(model, "user");
        SEL selector = NSSelectorFromString(@"pk");
        id authorPk = [user respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(user, selector) : nil;
        if (![authorPk isKindOfClass:NSString.class] || ![authorPk isEqualToString:pk]) continue;
        NSDictionary *info = TPJoinInfoForUser(user);
        if (info.count) return info;
    }
    return nil;
}

static void TPRequeueVisible(void) {
    BOOL scheduled = gPumpScheduled;
    gPumpScheduled = YES;
    for (TPAuthorBadgeLabel *b in gBadges.allObjects) {
        UIView *host = b.host;
        if (b.pk.length && TPHeaderVisible(host) && ![TPAuthorInfo infoForPk:b.pk]) [TPAuthorInfo requestPk:b.pk];
    }
    gPumpScheduled = scheduled;
}

// "台灣" / "Australia" / "澳大利亞" -> 🇹🇼 / 🇦🇺. Names come from Threads in the app's language, so
// they are matched against several locales' country names plus a few known spellings.
static NSString *TPFlagForCountry(NSString *name) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        NSArray *locales = @[@"zh_TW", @"zh_HK", @"zh_MO", @"zh_Hant", @"zh_Hans_CN", @"zh_Hans_SG", @"en_US", @"en_GB",
                             @"ja_JP", @"ko_KR", NSLocale.currentLocale.localeIdentifier];
        for (NSString *lid in locales) {
            NSLocale *loc = [NSLocale localeWithLocaleIdentifier:lid];
            for (NSString *cc in NSLocale.ISOCountryCodes) {
                NSString *n = [loc localizedStringForCountryCode:cc];
                if (n.length && !m[n]) m[n] = cc;
            }
        }
        NSDictionary *extra = @{ @"澳大利亞": @"AU", @"澳大利亚": @"AU", @"台灣": @"TW", @"臺灣": @"TW", @"台湾": @"TW",
                                 @"南韓": @"KR", @"韓國": @"KR", @"北韓": @"KP", @"中國": @"CN", @"中國大陸": @"CN",
                                 @"香港": @"HK", @"澳門": @"MO", @"紐西蘭": @"NZ", @"新西蘭": @"NZ", @"英國": @"GB",
                                 @"美國": @"US", @"阿拉伯聯合大公國": @"AE", @"Taiwan": @"TW", @"South Korea": @"KR",
                                 @"United States": @"US", @"United Kingdom": @"GB", @"Hong Kong": @"HK", @"Macau": @"MO" };
        [m addEntriesFromDictionary:extra];
        map = m;
    });
    NSString *key = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *cc = map[key];
    if (!cc) {
        for (NSString *suffix in @[@"特別行政區", @"特别行政区", @"SAR China", @"S.A.R."]) {
            NSRange r = [key rangeOfString:suffix];
            if (r.location != NSNotFound) { cc = map[[[key stringByReplacingCharactersInRange:r withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]]; if (cc) break; }
        }
    }
    if (cc.length != 2) return nil;
    NSMutableString *flag = [NSMutableString string];
    for (NSUInteger i = 0; i < 2; i++) {
        unichar c = [cc.uppercaseString characterAtIndex:i];
        if (c < 'A' || c > 'Z') return nil;
        uint32_t scalar = 0x1F1E6 + (c - 'A');
        uint32_t le = NSSwapHostIntToLittle(scalar);
        [flag appendString:[[NSString alloc] initWithBytes:&le length:4 encoding:NSUTF32LittleEndianStringEncoding]];
    }
    return flag;
}

static NSAttributedString *TPSpacer(CGFloat w) {
    NSTextAttachment *a = [NSTextAttachment new];
    a.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(MAX(w, 1), 1)] imageWithActions:^(UIGraphicsImageRendererContext *c) {}];
    a.bounds = CGRectMake(0, 0, w, 1);
    return [NSAttributedString attributedStringWithAttachment:a];
}

// Style: [NEW]  ( 🇹🇼 台灣 | 2023年7月 | #5,012,861 )  — one outlined capsule with hairline dividers.
// level 0 full, 1 drops the country name (when there's a flag) and the join number, 2 keeps only the flag.
// *prefixWidth receives the width of the NEW tag part, so the outline can start after it.
static NSAttributedString *TPBadgeText(NSDictionary *info, UIFont *font, UIColor *color, int level, CGFloat *prefixWidth) {
    BOOL showLoc = [TPPrefs boolForKey:TPKeyAuthorLocation];
    BOOL showJoin = [TPPrefs boolForKey:TPKeyAuthorJoined] && level < 2;
    BOOL showNew = [TPPrefs boolForKey:TPKeyAuthorNewBadge];
    BOOL showNumber = [TPPrefs boolForKey:TPKeyAuthorJoinNumber] && level == 0;
    NSString *loc = info[@"location"], *joined = info[@"joined"], *number = info[@"number"];
    BOOL hidden = [info[@"hidden"] boolValue];
    NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color };
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:font.pointSize - 1 weight:UIImageSymbolWeightMedium];

    NSMutableAttributedString *prefix = [NSMutableAttributedString new];
    void (^pill)(NSString *, UIColor *, UIColor *) = ^(NSString *label, UIColor *fill, UIColor *ink) {
        UIFont *bold = [UIFont systemFontOfSize:font.pointSize - 1 weight:UIFontWeightBold];
        CGSize ts = [label sizeWithAttributes:@{ NSFontAttributeName: bold }];
        CGSize ps = CGSizeMake(ceil(ts.width) + 10, ceil(font.lineHeight) + 2);
        UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:ps] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [fill setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, ps.width, ps.height) cornerRadius:ps.height / 2] fill];
            [label drawAtPoint:CGPointMake((ps.width - ts.width) / 2, (ps.height - ts.height) / 2)
                withAttributes:@{ NSFontAttributeName: bold, NSForegroundColorAttributeName: ink }];
        }];
        NSTextAttachment *a = [NSTextAttachment new];
        a.image = img;
        a.bounds = CGRectMake(0, (font.capHeight - ps.height) / 2, ps.width, ps.height);
        if (prefix.length) [prefix appendAttributedString:TPSpacer(4)];
        [prefix appendAttributedString:[NSAttributedString attributedStringWithAttachment:a]];
    };
    if (showNew && [TPAuthorInfo isNewAccount:joined]) pill(TPL(@"NEW"), [TPUI accent], UIColor.whiteColor);
    if ([TPPrefs boolForKey:TPKeyAuthorDefaultName] && [TPAuthorInfo isDefaultUsername:info[@"u"]]) {
        // Rendered into an image, so resolve the dynamic colours for the current appearance now.
        UITraitCollection *tc = UIScreen.mainScreen.traitCollection;
        pill(TPL(@"Default Name"), [UIColor.tertiarySystemFillColor resolvedColorWithTraitCollection:tc],
             [UIColor.secondaryLabelColor resolvedColorWithTraitCollection:tc]);
    }

    NSMutableArray<NSAttributedString *> *items = [NSMutableArray array];
    if (showLoc && (loc.length || hidden)) {
        NSMutableAttributedString *it = [NSMutableAttributedString new];
        // A hidden location gets the colour globe emoji, like the flags (and the Location Stats page).
        NSString *flag = loc.length ? TPFlagForCountry(loc) : @"🌐";
        if (flag) {
            [it appendAttributedString:[[NSAttributedString alloc] initWithString:flag attributes:attrs]];
        } else {
            UIImage *img = [[UIImage systemImageNamed:(loc.length ? @"mappin" : @"globe") withConfiguration:cfg]
                            imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
            if (img) {
                NSTextAttachment *a = [NSTextAttachment new];
                a.image = img;
                a.bounds = CGRectMake(0, (font.capHeight - img.size.height) / 2, img.size.width, img.size.height);
                [it appendAttributedString:[NSAttributedString attributedStringWithAttachment:a]];
            }
        }
        // Without a flag the name is the only way to tell the country, so it stays even when compact.
        NSString *name = loc.length ? loc : TPL(@"Not shared");
        if (level == 0 || (loc.length && !TPFlagForCountry(loc))) {
            [it appendAttributedString:TPSpacer(4)];
            [it appendAttributedString:[[NSAttributedString alloc] initWithString:name attributes:attrs]];
        }
        [items addObject:it];
    }
    if (showJoin && joined.length) {
        [items addObject:[[NSAttributedString alloc] initWithString:joined attributes:attrs]];
        if (showNumber && number.length) [items addObject:[[NSAttributedString alloc] initWithString:number attributes:attrs]];
    }

    NSMutableAttributedString *s = [prefix mutableCopy];
    CGFloat pw = 0;
    if (items.count) {
        if (prefix.length) [s appendAttributedString:TPSpacer(5)];
        pw = ceil([s boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 40) options:0 context:nil].size.width);
        if (!prefix.length) pw = 0;
        [s appendAttributedString:TPSpacer(7)];
        UIImage *line = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, ceil(font.capHeight) + 2)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [[color colorWithAlphaComponent:0.45] setFill];
            UIRectFill(CGRectMake(0, 0, 1, ceil(font.capHeight) + 2));
        }];
        for (NSUInteger i = 0; i < items.count; i++) {
            if (i) {
                [s appendAttributedString:TPSpacer(6)];
                NSTextAttachment *d = [NSTextAttachment new];
                d.image = line;
                d.bounds = CGRectMake(0, -1, 0.5, line.size.height);
                [s appendAttributedString:[NSAttributedString attributedStringWithAttachment:d]];
                [s appendAttributedString:TPSpacer(6)];
            }
            [s appendAttributedString:items[i]];
        }
        [s appendAttributedString:TPSpacer(7)];
    }
    if (prefixWidth) *prefixWidth = items.count ? pw : -1;
    // The flag emoji's font has a taller line than the 12 pt text, which pushed the baseline down
    // inside the capsule. Pin the line to the text font so the label centres it evenly.
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.minimumLineHeight = ps.maximumLineHeight = ceil(font.lineHeight);
    ps.lineBreakMode = NSLineBreakByClipping;
    [s addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0, s.length)];
    return s;
}

+ (CGFloat)extraHeaderHeight {
    if (![self enabled] || ![TPPrefs boolForKey:TPKeyAuthorOwnLine]) return 0;
    return ceil([UIFont systemFontOfSize:12].lineHeight) + 12;
}

+ (CGFloat)extraHeaderHeightForPk:(NSString *)pk {
    CGFloat extra = [self extraHeaderHeight];
    if (extra <= 0) return 0;
    NSDictionary *info = [self infoForPk:pk];
    BOOL visible = ([TPPrefs boolForKey:TPKeyAuthorLocation] && ([info[@"location"] length] || [info[@"hidden"] boolValue])) ||
                   ([TPPrefs boolForKey:TPKeyAuthorJoined] && [info[@"joined"] length]) ||
                   ([TPPrefs boolForKey:TPKeyAuthorNewBadge] && [self isNewAccount:info[@"joined"]]) ||
                   ([TPPrefs boolForKey:TPKeyAuthorDefaultName] && [self isDefaultUsername:info[@"u"]]);
    return visible ? extra : 0;
}

+ (void)layoutBadgeInHeader:(UIView *)contentView {
    TPAuthorBadgeLabel *badge = objc_getAssociatedObject(contentView, kBadgeKey);
    if (![self enabled]) { badge.hidden = YES; return; }

    NSString *pk = TPHeaderPk(contentView);
    UIView *title = TPIvarObject(contentView, "titleLabel") ?: TPIvarObject(contentView, "$__lazy_storage_$_titleLabel");
    if (!pk || ![title isKindOfClass:[UIView class]] || title.superview == nil) { badge.hidden = YES; return; }

    if (!badge) {
        badge = [[TPAuthorBadgeLabel alloc] initWithFrame:CGRectZero];
        badge.host = contentView;
        if (!gBadges) gBadges = [NSHashTable weakObjectsHashTable];
        [gBadges addObject:badge];
        objc_setAssociatedObject(contentView, kBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (badge.superview != title.superview) [title.superview addSubview:badge];
    badge.pk = pk;
    TPNoteHeaderName(pk, title);

    NSDictionary *info = [self infoForPk:pk];
    if (!info) {
        badge.hidden = YES;
        if (TPHeaderVisible(contentView)) [self requestPk:pk];
        return;
    }
    UIFont *font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    __block CGFloat prefixW = -1;
    NSAttributedString *text = TPBadgeText(info, font, UIColor.secondaryLabelColor, 0, &prefixW);
    if (!text.length) { badge.hidden = YES; return; }
    badge.attributedText = text;

    CGRect tf = title.frame;
    // Threads' text wrapper traps on a non-finite proposed size, so only ever pass the frame it
    // already laid itself out in.
    if (!(tf.size.width > 1 && tf.size.height > 1 && isfinite(tf.size.width) && isfinite(tf.size.height))) { badge.hidden = YES; return; }
    UIView *host = title.superview;
    CGFloat lineH = 22;
    CGFloat h = ceil(font.lineHeight) + 6;

    // Right edge of the free space on a line: the nearest visible sibling (edit / Threads icons,
    // ••• button) that sits on that line to the right of the name.
    CGFloat (^rightLimit)(CGFloat, CGFloat) = ^CGFloat(CGFloat top, CGFloat bottom) {
        CGFloat limit = host.bounds.size.width - 8;
        for (UIView *v in host.subviews) {
            if (v == title || v == badge || v.hidden || v.alpha < 0.05 || v.bounds.size.width < 2) continue;
            CGRect r = v.frame;
            if (CGRectGetMaxY(r) <= top || r.origin.y >= bottom) continue;
            if (r.origin.x <= tf.origin.x + 40) continue;
            limit = MIN(limit, r.origin.x - 6);
        }
        return limit;
    };

    // Most complete form that fits: full, then without the country name and icons, then flag only.
    CGFloat (^fit)(CGFloat) = ^CGFloat(CGFloat avail) {
        for (int level = 0; level < 3; level++) {
            CGFloat pw = prefixW;
            NSAttributedString *t = level ? TPBadgeText(info, font, UIColor.secondaryLabelColor, level, &pw) : text;
            if (!t.length) break;
            CGFloat w = ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 40) options:0 context:nil].size.width) + 1;
            if (w <= avail) { badge.attributedText = t; prefixW = pw; return w; }
        }
        return -1;
    };

    CGRect frame;
    CGFloat extra = [TPAuthorInfo extraHeaderHeightForPk:pk];
    if (extra > 0) {
        // Own line under the name (and the wrapped timestamp, if any).
        CGFloat y = CGRectGetMaxY(tf) + 4;
        CGFloat w = fit(host.bounds.size.width - 8 - tf.origin.x);
        if (w <= 0) { badge.hidden = YES; return; }
        frame = CGRectMake(tf.origin.x, round(y), w, h);
    } else if (tf.size.height > lineH + 8) {
        // Name and time wrapped onto two lines (e.g. full date format). The second line holds only
        // the end of the timestamp, so right-align the badge there.
        CGFloat top = tf.origin.y + lineH, bottom = CGRectGetMaxY(tf);
        CGFloat limit = rightLimit(top, bottom);
        CGFloat w = fit(limit - (tf.origin.x + 110));
        if (w <= 0) { badge.hidden = YES; return; }
        frame = CGRectMake(limit - w, round(top + (bottom - top - h) / 2), w, h);
    } else {
        NSAttributedString *titleText = TPTitleText(title, 0);
        CGFloat used = titleText.length ? ceil([titleText boundingRectWithSize:tf.size options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.width) : [title sizeThatFits:tf.size].width;
        if (!(used > 0) || !isfinite(used) || used > tf.size.width) used = tf.size.width;
        CGFloat x = tf.origin.x + used + 6;
        CGFloat limit = rightLimit(tf.origin.y, CGRectGetMaxY(tf));
        CGFloat w = fit(limit - x);
        if (w <= 0) { badge.hidden = YES; return; }
        frame = CGRectMake(x, round(tf.origin.y + (tf.size.height - h) / 2), w, h);
    }
    badge.frame = frame;
    badge.hidden = NO;

    // Outline capsule around the info (not the NEW tag).
    if (!badge.capsule) {
        badge.capsule = [CALayer layer];
        badge.capsule.borderWidth = 0.5;
        [badge.layer insertSublayer:badge.capsule atIndex:0];
    }
    badge.capsule.hidden = prefixW < 0;
    if (prefixW >= 0) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        badge.capsule.frame = CGRectMake(prefixW, 0.25, frame.size.width - prefixW - 0.5, frame.size.height - 0.5);
        badge.capsule.cornerRadius = (frame.size.height - 0.5) / 2;
        badge.capsule.borderColor = [UIColor.tertiaryLabelColor resolvedColorWithTraitCollection:badge.traitCollection].CGColor;
        [CATransaction commit];
    }
}

@end
