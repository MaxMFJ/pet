#import <Foundation/Foundation.h>

#import "PETSkillTimelineClip.h"

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillTimelineTrack : NSObject <NSCopying>

@property (nonatomic, copy) NSString *trackIdentifier;
@property (nonatomic, assign) PETSkillTimelineTrackType trackType;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) BOOL locked;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSMutableArray<PETSkillTimelineClip *> *clips;

- (NSArray<PETSkillTimelineClip *> *)clipsActiveAtTime:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END
