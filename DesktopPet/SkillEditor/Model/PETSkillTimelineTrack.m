#import "PETSkillTimelineTrack.h"

@implementation PETSkillTimelineTrack

- (instancetype)init {
    self = [super init];
    if (self) {
        _trackIdentifier = NSUUID.UUID.UUIDString;
        _displayName = @"Track";
        _clips = [NSMutableArray array];
    }
    return self;
}

- (NSArray<PETSkillTimelineClip *> *)clipsActiveAtTime:(NSTimeInterval)time {
    NSMutableArray<PETSkillTimelineClip *> *active = [NSMutableArray array];
    for (PETSkillTimelineClip *clip in self.clips) {
        if ([clip containsTime:time]) {
            [active addObject:clip];
        }
    }
    return active.copy;
}

- (id)copyWithZone:(NSZone *)zone {
    PETSkillTimelineTrack *copy = [[PETSkillTimelineTrack allocWithZone:zone] init];
    copy.trackIdentifier = self.trackIdentifier.copy;
    copy.trackType = self.trackType;
    copy.displayName = self.displayName.copy;
    copy.locked = self.locked;
    copy.muted = self.muted;
    copy.clips = [[NSMutableArray alloc] initWithArray:self.clips copyItems:YES];
    return copy;
}

@end
