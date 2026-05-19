#import "PETSkillTimelinePlayer.h"

#import "../../SkillEditor/Model/PETSkillTimelineDocument.h"
#import "../../SkillEditor/Model/PETSkillTimelineEnums.h"
#import "../../SkillEditor/Model/PETSkillTimelineTrack.h"
#import "../../SkillEditor/Model/PETSkillTimelineClip.h"
#import "../../UI/PETSpineMetalView.h"

@interface PETSkillTimelinePlayer ()

@property (nonatomic, assign, readwrite) NSTimeInterval currentTime;
@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, strong) NSMutableSet<NSString *> *firedInstantClipIdentifiers;

@end

@implementation PETSkillTimelinePlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        _facingRight = YES;
        _firedInstantClipIdentifiers = [NSMutableSet set];
    }
    return self;
}

- (void)setDocument:(PETSkillTimelineDocument *)document {
    _document = document;
    self.currentTime = document.playheadTime;
    [self.firedInstantClipIdentifiers removeAllObjects];
}

- (void)play {
    self.isPlaying = YES;
}

- (void)pause {
    self.isPlaying = NO;
}

- (void)seekToTime:(NSTimeInterval)time {
    if (self.document == nil) {
        return;
    }
    self.currentTime = MAX(0.0, MIN(time, self.document.duration));
    self.document.playheadTime = self.currentTime;
    [self.firedInstantClipIdentifiers removeAllObjects];
    [self syncToCurrentTime];
    if (self.onTimeChanged != nil) {
        self.onTimeChanged(self.currentTime);
    }
}

- (void)stepFrame:(NSInteger)direction {
    [self seekToTime:self.currentTime + direction * (1.0 / 60.0)];
}

- (void)tick:(NSTimeInterval)delta {
    if (!self.isPlaying || self.document == nil) {
        return;
    }
    NSTimeInterval nextTime = self.currentTime + delta;
    if (nextTime >= self.document.duration) {
        if (self.document.loopPlayback) {
            nextTime = fmod(nextTime, self.document.duration);
            [self.firedInstantClipIdentifiers removeAllObjects];
        } else {
            nextTime = self.document.duration;
            self.isPlaying = NO;
        }
    }
    self.currentTime = nextTime;
    self.document.playheadTime = nextTime;
    [self processInstantEvents];
    [self syncToCurrentTime];
    if (self.onTimeChanged != nil) {
        self.onTimeChanged(nextTime);
    }
}

- (void)syncToCurrentTime {
    if (self.spineView == nil || self.document == nil) {
        return;
    }

    NSString *animation = [self resolvedAnimationNameAtCurrentTime];
    if (![self.spineView.currentState isEqualToString:animation]) {
        [self.spineView playState:animation loop:NO];
    }
    [self.spineView seekToAnimationTime:self.currentTime];
    self.spineView.activeShaderPayload = [self primaryActiveShaderPayload];
    [self.spineView redrawSpineFrame];
}

- (NSString *)resolvedAnimationNameAtCurrentTime {
    NSString *animation = self.document.characterAnimation ?: @"idle";
    PETSkillTimelineTrack *characterTrack = [self.document trackWithType:PETSkillTimelineTrackTypeCharacter createIfNeeded:NO];
    for (PETSkillTimelineClip *clip in [characterTrack clipsActiveAtTime:self.currentTime]) {
        NSString *clipAnimation = [clip.payload[@"animation"] isKindOfClass:NSString.class] ? clip.payload[@"animation"] : nil;
        if (clipAnimation.length > 0) {
            animation = clipAnimation;
            break;
        }
    }
    return animation;
}

- (NSArray<NSDictionary<NSString *, id> *> *)activeHitboxPayloads {
    return [self activePayloadsForTrackType:PETSkillTimelineTrackTypeHitbox];
}

- (NSArray<NSDictionary<NSString *, id> *> *)activeShaderPayloads {
    return [self activePayloadsForTrackType:PETSkillTimelineTrackTypeShader];
}

- (nullable NSDictionary<NSString *, id> *)primaryActiveShaderPayload {
    NSArray<NSDictionary<NSString *, id> *> *payloads = [self activeShaderPayloads];
    return payloads.firstObject;
}

- (NSArray<NSDictionary<NSString *, id> *> *)activePayloadsForTrackType:(PETSkillTimelineTrackType)trackType {
    if (self.document == nil) {
        return @[];
    }
    PETSkillTimelineTrack *track = [self.document trackWithType:trackType createIfNeeded:NO];
    if (track == nil || track.muted) {
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *payloads = [NSMutableArray array];
    for (PETSkillTimelineClip *clip in [track clipsActiveAtTime:self.currentTime]) {
        [payloads addObject:clip.payload ?: @{}];
    }
    return payloads.copy;
}

- (void)processInstantEvents {
    PETSkillTimelineTrack *eventTrack = [self.document trackWithType:PETSkillTimelineTrackTypeEvent createIfNeeded:NO];
    if (eventTrack == nil || eventTrack.muted) {
        return;
    }
    for (PETSkillTimelineClip *clip in eventTrack.clips) {
        if (clip.clipKind != PETSkillTimelineClipKindInstant) {
            continue;
        }
        if (fabs(self.currentTime - clip.startTime) > (1.0 / 60.0)) {
            continue;
        }
        if ([self.firedInstantClipIdentifiers containsObject:clip.clipIdentifier]) {
            continue;
        }
        [self.firedInstantClipIdentifiers addObject:clip.clipIdentifier];
        NSString *eventType = [clip.payload[@"eventType"] isKindOfClass:NSString.class] ? clip.payload[@"eventType"] : @"custom";
        NSDictionary *params = [clip.payload[@"params"] isKindOfClass:NSDictionary.class] ? clip.payload[@"params"] : clip.payload;
        if (self.onEventFired != nil) {
            self.onEventFired(eventType, params ?: @{});
        }
    }
}

@end
