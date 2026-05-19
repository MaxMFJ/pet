#import "PETSkillTimelineDocument.h"

NSNotificationName const PETSkillTimelineDocumentDidChangeNotification = @"PETSkillTimelineDocumentDidChangeNotification";

@implementation PETSkillTimelineDocument

+ (instancetype)emptyDocument {
    PETSkillTimelineDocument *document = [[PETSkillTimelineDocument alloc] init];
    document.skillIdentifier = @"new_skill";
    document.displayName = @"New Skill";
    document.formatVersion = 1;
    document.characterProfileId = @"";
    document.characterAnimation = @"idle";
    document.duration = 1.0;
    document.playheadTime = 0.0;
    [document ensureDefaultTracks];
    return document;
}

+ (instancetype)sampleDocument {
    PETSkillTimelineDocument *document = [self emptyDocument];
    document.skillIdentifier = @"slash_01";
    document.displayName = @"Slash A";
    document.duration = 1.2;
    document.characterAnimation = @"attack";

    PETSkillTimelineTrack *hitboxTrack = [document trackWithType:PETSkillTimelineTrackTypeHitbox createIfNeeded:YES];
    PETSkillTimelineClip *hitClip = [[PETSkillTimelineClip alloc] init];
    hitClip.trackType = PETSkillTimelineTrackTypeHitbox;
    hitClip.startTime = 0.15;
    hitClip.endTime = 0.22;
    hitClip.payload = @{
        @"shape": @"rect",
        @"socket": @"root",
        @"x": @0,
        @"y": @0,
        @"width": @120,
        @"height": @60,
        @"damage": @120,
        @"windowId": @"strike_hit",
        @"reactionId": @"hit_stun_light",
        @"collisionMode": @"pixelOverlap"
    };
    [hitboxTrack.clips addObject:hitClip];

    PETSkillTimelineTrack *fxTrack = [document trackWithType:PETSkillTimelineTrackTypeFX createIfNeeded:YES];
    PETSkillTimelineClip *fxClip = [[PETSkillTimelineClip alloc] init];
    fxClip.trackType = PETSkillTimelineTrackTypeFX;
    fxClip.startTime = 0.12;
    fxClip.endTime = 0.45;
    fxClip.payload = @{
        @"asset": @"slash_fx",
        @"assetType": @"pngSequence",
        @"socket": @"root",
        @"offsetX": @12,
        @"offsetY": @-8,
        @"rotation": @15,
        @"scale": @1.2,
        @"flipX": @NO,
        @"blendMode": @"additive"
    };
    [fxTrack.clips addObject:fxClip];

    PETSkillTimelineTrack *shaderTrack = [document trackWithType:PETSkillTimelineTrackTypeShader createIfNeeded:YES];
    PETSkillTimelineClip *shaderClip = [[PETSkillTimelineClip alloc] init];
    shaderClip.trackType = PETSkillTimelineTrackTypeShader;
    shaderClip.startTime = 0.08;
    shaderClip.endTime = 0.28;
    shaderClip.payload = @{
        @"shader": @"glow",
        @"params": @{ @"intensity": @1.4 }
    };
    [shaderTrack.clips addObject:shaderClip];
    return document;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _formatVersion = 1;
        _tracks = [NSMutableArray array];
        _skillIdentifier = @"new_skill";
        _displayName = @"New Skill";
        _characterAnimation = @"idle";
        _duration = 1.0;
    }
    return self;
}

- (PETSkillTimelineTrack *)trackWithType:(PETSkillTimelineTrackType)trackType
                          createIfNeeded:(BOOL)createIfNeeded {
    for (PETSkillTimelineTrack *track in self.tracks) {
        if (track.trackType == trackType) {
            return track;
        }
    }
    if (!createIfNeeded) {
        return nil;
    }
    PETSkillTimelineTrack *track = [[PETSkillTimelineTrack alloc] init];
    track.trackType = trackType;
    track.trackIdentifier = [NSString stringWithFormat:@"%@_%@", PETSkillTimelineStringFromTrackType(trackType), NSUUID.UUID.UUIDString];
    switch (trackType) {
        case PETSkillTimelineTrackTypeCharacter:
            track.displayName = @"Character";
            break;
        case PETSkillTimelineTrackTypeFX:
            track.displayName = @"FX";
            break;
        case PETSkillTimelineTrackTypeHitbox:
            track.displayName = @"Hitbox";
            break;
        case PETSkillTimelineTrackTypeShader:
            track.displayName = @"Shader";
            break;
        case PETSkillTimelineTrackTypeEvent:
            track.displayName = @"Event";
            break;
    }
    [self.tracks addObject:track];
    return track;
}

- (void)ensureDefaultTracks {
    [self trackWithType:PETSkillTimelineTrackTypeCharacter createIfNeeded:YES];
    [self trackWithType:PETSkillTimelineTrackTypeFX createIfNeeded:YES];
    [self trackWithType:PETSkillTimelineTrackTypeHitbox createIfNeeded:YES];
    [self trackWithType:PETSkillTimelineTrackTypeShader createIfNeeded:YES];
    [self trackWithType:PETSkillTimelineTrackTypeEvent createIfNeeded:YES];

    PETSkillTimelineTrack *characterTrack = [self trackWithType:PETSkillTimelineTrackTypeCharacter createIfNeeded:NO];
    if (characterTrack.clips.count == 0) {
        PETSkillTimelineClip *clip = [[PETSkillTimelineClip alloc] init];
        clip.trackType = PETSkillTimelineTrackTypeCharacter;
        clip.startTime = 0.0;
        clip.endTime = self.duration;
        clip.payload = @{
            @"animation": self.characterAnimation ?: @"idle",
            @"loop": @NO,
            @"playbackRate": @1.0
        };
        [characterTrack.clips addObject:clip];
    }
}

- (void)notifyChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:PETSkillTimelineDocumentDidChangeNotification object:self];
}

- (void)applyStateFromDocument:(PETSkillTimelineDocument *)source preservePlayhead:(BOOL)preservePlayhead {
    if (source == nil) {
        return;
    }
    NSTimeInterval savedPlayhead = self.playheadTime;
    self.skillIdentifier = source.skillIdentifier.copy;
    self.displayName = source.displayName.copy;
    self.formatVersion = source.formatVersion;
    self.characterProfileId = source.characterProfileId.copy;
    self.characterAnimation = source.characterAnimation.copy;
    self.duration = source.duration;
    self.loopPlayback = source.loopPlayback;
    self.tracks = [[NSMutableArray alloc] initWithArray:source.tracks copyItems:YES];
    if (preservePlayhead) {
        self.playheadTime = MIN(savedPlayhead, self.duration);
    } else {
        self.playheadTime = MIN(source.playheadTime, self.duration);
    }
}

@end
