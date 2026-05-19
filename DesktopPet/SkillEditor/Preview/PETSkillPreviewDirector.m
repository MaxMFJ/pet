#import "PETSkillPreviewDirector.h"

#import "../../GameEngine/Skill/PETSkillTimelinePlayer.h"
#import "../../UI/PETSpineMetalView.h"
#import "../Model/PETSkillTimelineDocument.h"
#import "../Model/PETSkillTimelineEnums.h"
#import "../Model/PETSkillTimelineTrack.h"
#import "../Model/PETSkillTimelineClip.h"
#import "PETHitboxOverlayView.h"
#import "PETFXOverlayView.h"
#import "PETShaderOverlayView.h"
#import "PETFXPreviewInstance.h"

@interface PETSkillPreviewDirector ()

@property (nonatomic, strong) PETSkillTimelinePlayer *player;
@property (nonatomic, strong, nullable) NSTimer *playbackTimer;
@property (nonatomic, assign, readwrite) BOOL isPlaying;

@end

@implementation PETSkillPreviewDirector

- (instancetype)init {
    self = [super init];
    if (self) {
        _player = [[PETSkillTimelinePlayer alloc] init];
        _facingRight = YES;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)setDocument:(PETSkillTimelineDocument *)document {
    _document = document;
    self.player.document = document;
}

- (void)setSpineView:(PETSpineMetalView *)spineView {
    _spineView = spineView;
    self.player.spineView = spineView;
}

- (void)setFacingRight:(BOOL)facingRight {
    _facingRight = facingRight;
    self.player.facingRight = facingRight;
}

- (void)start {
    if (self.playbackTimer != nil) {
        return;
    }
    self.isPlaying = YES;
    [self.player play];
    self.playbackTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                         repeats:YES
                                                           block:^(NSTimer *timer) {
        (void)timer;
        [self onPlaybackTick];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.playbackTimer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    self.isPlaying = NO;
    [self.player pause];
    [self.playbackTimer invalidate];
    self.playbackTimer = nil;
}

- (void)onPlaybackTick {
    [self.player tick:(1.0 / 60.0)];
    [self refreshOverlays];
    [self.document notifyChanged];
}

- (void)seekToTime:(NSTimeInterval)time {
    [self.player seekToTime:time];
    [self refreshOverlays];
}

- (void)stepFrame:(NSInteger)direction {
    [self.player stepFrame:direction];
    [self refreshOverlays];
}

- (void)syncPreviewToPlayhead {
    [self.player syncToCurrentTime];
    [self refreshOverlays];
}

- (void)refreshOverlays {
    if (self.document == nil) {
        return;
    }

    NSTimeInterval time = self.player.currentTime;
    self.hitboxOverlay.facingRight = self.facingRight;
    self.hitboxOverlay.activeHitboxes = [self.player activeHitboxPayloads];
    [self.hitboxOverlay setNeedsDisplay:YES];

    NSMutableArray<PETFXPreviewInstance *> *activeFX = [NSMutableArray array];
    PETSkillTimelineTrack *fxTrack = [self.document trackWithType:PETSkillTimelineTrackTypeFX createIfNeeded:NO];
    for (PETSkillTimelineClip *clip in [fxTrack clipsActiveAtTime:time]) {
        NSTimeInterval localTime = time - clip.startTime;
        [activeFX addObject:[PETFXPreviewInstance instanceWithClip:clip clipLocalTime:localTime]];
    }
    self.fxOverlay.facingRight = self.facingRight;
    self.fxOverlay.activeInstances = activeFX.copy;
    [self.fxOverlay setNeedsDisplay:YES];

    if (self.shaderOverlay != nil) {
        self.shaderOverlay.activeShaders = [self.player activeShaderPayloads];
        [self.shaderOverlay setNeedsDisplay:YES];
    }
}

@end
