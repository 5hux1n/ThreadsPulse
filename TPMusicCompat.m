#import "TPMusicCompat.h"
#import "TPMusicAttachment.h"
#import "TPDownloader.h"
#import "TPUI.h"
#import "TPHUD.h"
#import "TPLocalization.h"
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

void TPMusicUpdateMedia(id media, NSDictionary *dictionary) {
    id info = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[@"text_app_music_info"] : nil;
    if (!info) return; // Partial updates need not repeat the attachment.
    TPMusicAttachment *attachment = [TPMusicAttachment attachmentWithDictionary:info];
    objc_setAssociatedObject(media, &kTPMusicAttachment, attachment, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void TPMusicLayoutCell(UIView *cell) {
    id media = [TPDownloader ivarValue:cell name:@"media"];
    TPMusicAttachment *attachment = objc_getAssociatedObject(media, &kTPMusicAttachment);
    UIView *card = [TPDownloader ivarValue:cell name:@"tombstoneView"];
    UIView *label = [TPDownloader ivarValue:card name:@"label"];
    TPMusicButton *button = objc_getAssociatedObject(cell, &kTPMusicButton);
    if (!attachment || !card || !label) {
        if (button.superview == card) label.hidden = NO;
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
    label.hidden = YES;
    [card bringSubviewToFront:button];
}
