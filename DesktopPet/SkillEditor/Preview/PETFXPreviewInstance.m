#import "PETFXPreviewInstance.h"

#import "../Model/PETSkillTimelineClip.h"
#import "PETFXAssetCatalog.h"

@implementation PETFXPreviewInstance

+ (instancetype)instanceWithClip:(PETSkillTimelineClip *)clip clipLocalTime:(NSTimeInterval)clipLocalTime {
    PETFXPreviewInstance *instance = [[PETFXPreviewInstance alloc] init];
    instance.clip = clip;
    instance.payload = clip.payload ?: @{};
    instance.clipLocalTime = MAX(0.0, clipLocalTime);

    NSString *asset = [clip.payload[@"asset"] isKindOfClass:NSString.class] ? clip.payload[@"asset"] : @"fx";
    PETFXSequence *sequence = [PETFXAssetCatalog.sharedCatalog sequenceNamed:asset];
    if (sequence.frames.count > 0) {
        NSUInteger frameIndex = (NSUInteger)(instance.clipLocalTime * sequence.framesPerSecond);
        instance.currentFrame = [sequence frameAtIndex:frameIndex];
        instance.usesPlaceholder = NO;
    } else {
        instance.currentFrame = nil;
        instance.usesPlaceholder = YES;
    }
    return instance;
}

@end
