#import "TPMusicCompat.h"
#import "TPMusicAttachment.h"
#import "TPDownloader.h"
#import "TPUI.h"
#import "TPHUD.h"
#import "TPLocalization.h"
#import "TPPrefs.h"
#import <AVKit/AVKit.h>
#import <objc/runtime.h>

static char kTPMusicAttachment, kTPMusicButton;

@interface TPMusicPlayerController : AVPlayerViewController
@property (nonatomic) NSTimeInterval musicStartTime;
@property (nonatomic) BOOL started;
@end
@implementation TPMusicPlayerController
- (instancetype)initWithAttachment:(TPMusicAttachment *)attachment {
    if ((self = [super init])) {
        self.musicStartTime = attachment.startTime;
        self.player = [AVPlayer playerWithURL:attachment.URL];
        [self.player.currentItem addObserver:self forKeyPath:@"status" options:0 context:&kTPMusicAttachment];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pauseMusic) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}
- (void)dealloc {
    [self.player.currentItem removeObserver:self forKeyPath:@"status" context:&kTPMusicAttachment];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.player pause];
}
- (void)pauseMusic { [self.player pause]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startWhenReady];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.player pause];
}
- (void)startWhenReady {
    if (self.started || !self.view.window || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || self.player.currentItem.status != AVPlayerItemStatusReadyToPlay) return;
    self.started = YES;
    __weak TPMusicPlayerController *weakSelf = self;
    [self.player seekToTime:CMTimeMakeWithSeconds(self.musicStartTime, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            TPMusicPlayerController *controller = weakSelf;
            if (finished && controller.view.window && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) [controller.player play];
        });
    }];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kTPMusicAttachment) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
            [self.player pause];
            [TPHUD toast:TPL(@"Unable to play this music attachment")];
        } else [self startWhenReady];
    });
}
@end

@interface TPMusicButton : UIButton
@property (nonatomic, strong) TPMusicAttachment *attachment;
@end
@implementation TPMusicButton
- (void)playMusic {
    if (!self.window || !self.attachment) return;
    UIViewController *presenter = TPTopViewController();
    if (!presenter || presenter.isBeingDismissed) return;
    TPMusicPlayerController *player = [[TPMusicPlayerController alloc] initWithAttachment:self.attachment];
    [presenter presentViewController:player animated:YES completion:nil];
}
@end

// Explains a rejected payload once per distinct reason, so a server-side change is
// visible instead of silently turning the play button into a bare tombstone.
static void TPMusicNoteRejection(NSDictionary *info) {
    if (![TPPrefs boolForKey:TPKeyDebugToast]) return;
    NSDictionary *diagnostics = [TPMusicAttachment diagnosticsForDictionary:info];
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%@", diagnostics[@"denied"], diagnostics[@"manifests"], diagnostics[@"title"], diagnostics[@"error"]];
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    if ([seen containsObject:signature] || seen.count >= 8) return;
    [seen addObject:signature];
    NSString *reason = [diagnostics[@"manifests"] integerValue] ? @"no-playable-manifest" : @"no-manifest";
    NSString *detail = [diagnostics[@"error"] length] ? diagnostics[@"error"] : @"-";
    dispatch_async(dispatch_get_main_queue(), ^{
        [TPHUD toast:[NSString stringWithFormat:@"[TP] music %@ · %@", reason, detail]];
    });
}

void TPMusicUpdateMedia(id media, NSDictionary *dictionary) {
    id info = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[@"text_app_music_info"] : nil;
    if (!info) return; // Partial updates need not repeat the attachment.
    TPMusicAttachment *attachment = [TPMusicAttachment attachmentWithDictionary:info];
    if (!attachment) TPMusicNoteRejection(info);
    objc_setAssociatedObject(media, &kTPMusicAttachment, attachment, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *TPMusicTombstoneText(UIView *card, UIView *label) {
    if (label) return label;
    // 410 renders the tombstone text with IGCoreTextView and no `label` ivar.
    for (UIView *sub in card.subviews) {
        if ([sub isKindOfClass:UILabel.class] || [NSStringFromClass(sub.class) containsString:@"Text"]) return sub;
    }
    return nil;
}

void TPMusicLayoutCell(UIView *cell) {
    id media = [TPDownloader ivarValue:cell name:@"media"];
    TPMusicAttachment *attachment = objc_getAssociatedObject(media, &kTPMusicAttachment);
    UIView *tombstone = [TPDownloader ivarValue:cell name:@"tombstoneView"];
    UIView *card = tombstone ?: cell;
    UIView *label = tombstone ? [TPDownloader ivarValue:tombstone name:@"label"] : nil;
    UIView *text = tombstone ? TPMusicTombstoneText(tombstone, label) : nil;
    TPMusicButton *button = objc_getAssociatedObject(cell, &kTPMusicButton);
    if (!attachment) {
        if (button.superview == card) text.hidden = NO;
        [button removeFromSuperview];
        button.attachment = nil;
        return;
    }
    if (!button) {
        button = [TPMusicButton buttonWithType:UIButtonTypeSystem];
        [button addTarget:button action:@selector(playMusic) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(cell, &kTPMusicButton, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.attachment = attachment;
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = attachment.title;
    configuration.subtitle = attachment.artist;
    configuration.image = [UIImage systemImageNamed:@"play.circle"];
    configuration.imagePadding = 8;
    configuration.titlePadding = 2;
    configuration.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(4, 10, 4, 10);
    button.configuration = configuration;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    button.tintColor = UIColor.labelColor;
    button.accessibilityLabel = [NSString stringWithFormat:@"%@ · %@", attachment.title, attachment.artist];
    button.accessibilityHint = TPL(@"Tap to play music");
    button.frame = card.bounds;
    if (button.superview != card) [card addSubview:button];
    text.hidden = YES;
    [card bringSubviewToFront:button];
}
