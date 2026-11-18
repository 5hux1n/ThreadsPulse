#import "TPUpdateChecker.h"
#import "TPPrefs.h"
#import "TPLocalization.h"
#import "TPHUD.h"
#import "TPUI.h"
#import "TPVersion.h"
#import "TPWelcomeViewController.h"
#import <SafariServices/SafariServices.h>

static NSString *const kTPLatestReleaseAPI = @"https://api.github.com/repos/mumuisdog/ThreadsPulse/releases/latest";
static NSString *const kTPLastCheckKey = @"tp_update_last_check";
static NSString *const kTPSkippedKey   = @"tp_update_skipped";
static const NSTimeInterval kTPCheckInterval = 24 * 60 * 60;

// -1, 0 or 1, comparing dotted numbers ("1.30.1" vs "1.31").
static NSComparisonResult TPCompareVersions(NSString *a, NSString *b) {
    NSArray *pa = [a componentsSeparatedByString:@"."], *pb = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(pa.count, pb.count); i++) {
        NSInteger x = i < pa.count ? [pa[i] integerValue] : 0, y = i < pb.count ? [pb[i] integerValue] : 0;
        if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

// The release notes hold Chinese first and English after a "---" line: pick the part for the
// current language and turn the Markdown into plain text for an alert.
static NSString *TPPlainNotes(NSString *body) {
    if (!body.length) return @"";
    NSArray *parts = [body componentsSeparatedByString:@"\n---"];
    BOOL chinese = [TPL(@"Unknown") isEqualToString:@"無法辨識"] || [TPL(@"Unknown") isEqualToString:@"无法识别"];
    NSString *notes = parts.count > 1 && !chinese ? parts[1] : parts[0];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *raw in [notes componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *l = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!l.length || [l hasPrefix:@"## "] || [l isEqualToString:@"---"]) continue;   // the title repeats the version
        if ([l hasPrefix:@"### "]) l = [NSString stringWithFormat:@"\n%@", [l substringFromIndex:4]];
        else if ([l hasPrefix:@"- "]) l = [@"• " stringByAppendingString:[l substringFromIndex:2]];
        l = [l stringByReplacingOccurrencesOfString:@"**" withString:@""];
        l = [l stringByReplacingOccurrencesOfString:@"`" withString:@""];
        l = [l stringByReplacingOccurrencesOfString:@"\\[([^\\]]*)\\]\\([^)]*\\)" withString:@"$1"
                                            options:NSRegularExpressionSearch range:NSMakeRange(0, l.length)];
        [out addObject:l];
    }
    NSString *text = [[out componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Installation steps and credits aren't news.
    for (NSString *cut in @[@"\n安裝", @"\nInstall"]) {
        NSRange r = [text rangeOfString:cut];
        if (r.location != NSNotFound) text = [text substringToIndex:r.location];
    }
    if (text.length > 700) text = [[text substringToIndex:700] stringByAppendingString:@"…"];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@implementation TPUpdateChecker

+ (void)fetch:(void (^)(NSString *version, NSString *url, NSString *notes, NSError *error))done {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kTPLatestReleaseAPI]];
    req.timeoutInterval = 15;
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:[@"ThreadsPulse/" stringByAppendingString:TP_VERSION] forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSDictionary *j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *tag = [j isKindOfClass:[NSDictionary class]] ? j[@"tag_name"] : nil;
        NSString *version = [tag isKindOfClass:[NSString class]] ? [tag stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV "]] : nil;
        NSString *url = [j[@"html_url"] isKindOfClass:[NSString class]] ? j[@"html_url"] : nil;
        NSString *body = [j[@"body"] isKindOfClass:[NSString class]] ? j[@"body"] : nil;
        NSError *e = err ?: (version.length ? nil : [NSError errorWithDomain:@"TPUpdate" code:1 userInfo:nil]);
        dispatch_async(dispatch_get_main_queue(), ^{ done(version, url, TPPlainNotes(body), e); });
    }] resume];
}

+ (void)checkAutomatically {
    if (![TPPrefs boolForKey:TPKeyAutoUpdateCheck]) return;
    NSUserDefaults *d = [TPPrefs defaults];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - [d doubleForKey:kTPLastCheckKey] < kTPCheckInterval) return;
    static BOOL running;
    if (running) return;
    running = YES;
    [self fetch:^(NSString *version, NSString *url, NSString *notes, NSError *error) {
        running = NO;
        if (error) return;   // try again on the next launch
        [d setDouble:now forKey:kTPLastCheckKey];
        if (TPCompareVersions(TP_VERSION, version) != NSOrderedAscending) return;
        if ([[d stringForKey:kTPSkippedKey] isEqualToString:version]) return;
        [self offerVersion:version url:url notes:notes attempt:0];
    }];
}

+ (void)checkNow {
    [TPHUD toast:TPL(@"Checking for updates…")];
    [self fetch:^(NSString *version, NSString *url, NSString *notes, NSError *error) {
        if (error) { [TPHUD toast:TPL(@"Couldn't check for updates. Try again later.")]; return; }
        [[TPPrefs defaults] setDouble:[NSDate date].timeIntervalSince1970 forKey:kTPLastCheckKey];
        if (TPCompareVersions(TP_VERSION, version) != NSOrderedAscending) {
            [TPHUD toast:[NSString stringWithFormat:@"%@ (%@)", TPL(@"You're on the latest version"), TP_VERSION]];
            return;
        }
        [self offerVersion:version url:url notes:notes attempt:0];
    }];
}

// Waits for a quiet moment (no welcome screen, alert or transition on screen) before asking.
+ (void)offerVersion:(NSString *)version url:(NSString *)url notes:(NSString *)notes attempt:(NSInteger)attempt {
    UIViewController *top = TPTopViewController();
    BOOL busy = !top || !top.view.window || top.isBeingPresented || top.isBeingDismissed
             || [top isKindOfClass:[UIAlertController class]] || [top isKindOfClass:[TPWelcomeViewController class]]
             || UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    if (busy) {
        if (attempt >= 10) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self offerVersion:version url:url notes:notes attempt:attempt + 1];
        });
        return;
    }
    NSString *message = [NSString stringWithFormat:TPL(@"You're on %@"), TP_VERSION];
    if (notes.length) message = [message stringByAppendingFormat:@"\n\n%@", notes];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:TPL(@"ThreadsPulse %@ Is Available"), version]
                                                               message:message preferredStyle:UIAlertControllerStyleAlert];
    // Left-align the notes; a centred bullet list is hard to read.
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentLeft;
    NSAttributedString *body = [[NSAttributedString alloc] initWithString:message attributes:@{
        NSParagraphStyleAttributeName: ps,
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote],
        NSForegroundColorAttributeName: UIColor.labelColor }];
    @try { [a setValue:body forKey:@"attributedMessage"]; } @catch (NSException *e) {}

    [a addAction:[UIAlertAction actionWithTitle:TPL(@"Download") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSURL *u = [NSURL URLWithString:url ?: @"https://github.com/mumuisdog/ThreadsPulse/releases/latest"];
        UIViewController *t = TPTopViewController();
        if (!u || !t) return;
        SFSafariViewController *sf = [[SFSafariViewController alloc] initWithURL:u];
        sf.dismissButtonStyle = SFSafariViewControllerDismissButtonStyleClose;
        [t presentViewController:sf animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:TPL(@"Skip This Version") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[TPPrefs defaults] setObject:version forKey:kTPSkippedKey];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:TPL(@"Later") style:UIAlertActionStyleCancel handler:nil]];
    a.preferredAction = a.actions.firstObject;
    a.view.tintColor = [TPUI accent];
    [top presentViewController:a animated:YES completion:nil];
}

@end
