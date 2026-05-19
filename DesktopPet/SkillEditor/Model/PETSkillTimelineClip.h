#import <Foundation/Foundation.h>

#import "PETSkillTimelineEnums.h"

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillTimelineClip : NSObject <NSCopying>

@property (nonatomic, copy) NSString *clipIdentifier;
@property (nonatomic, assign) PETSkillTimelineTrackType trackType;
@property (nonatomic, assign) PETSkillTimelineClipKind clipKind;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval endTime;
@property (nonatomic, copy) NSDictionary<NSString *, id> *payload;

- (BOOL)containsTime:(NSTimeInterval)time;
- (NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END
