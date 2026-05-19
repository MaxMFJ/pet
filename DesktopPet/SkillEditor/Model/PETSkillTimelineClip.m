#import "PETSkillTimelineClip.h"

@implementation PETSkillTimelineClip

- (instancetype)init {
    self = [super init];
    if (self) {
        _clipIdentifier = NSUUID.UUID.UUIDString;
        _clipKind = PETSkillTimelineClipKindSpan;
        _payload = @{};
    }
    return self;
}

- (BOOL)containsTime:(NSTimeInterval)time {
    if (self.clipKind == PETSkillTimelineClipKindInstant) {
        return fabs(time - self.startTime) < (1.0 / 120.0);
    }
    return time + 0.0001 >= self.startTime && time - 0.0001 <= self.endTime;
}

- (NSTimeInterval)duration {
    if (self.clipKind == PETSkillTimelineClipKindInstant) {
        return 0.0;
    }
    return MAX(0.0, self.endTime - self.startTime);
}

- (id)copyWithZone:(NSZone *)zone {
    PETSkillTimelineClip *copy = [[PETSkillTimelineClip allocWithZone:zone] init];
    copy.clipIdentifier = self.clipIdentifier.copy;
    copy.trackType = self.trackType;
    copy.clipKind = self.clipKind;
    copy.startTime = self.startTime;
    copy.endTime = self.endTime;
    copy.payload = self.payload.copy;
    return copy;
}

@end
