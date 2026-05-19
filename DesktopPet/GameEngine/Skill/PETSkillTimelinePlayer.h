#import <Foundation/Foundation.h>

@class PETSkillTimelineDocument;
@class PETSpineMetalView;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillTimelinePlayer : NSObject

@property (nonatomic, strong) PETSkillTimelineDocument *document;
@property (nonatomic, weak, nullable) PETSpineMetalView *spineView;
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign) BOOL facingRight;

@property (nonatomic, copy, nullable) void (^onTimeChanged)(NSTimeInterval time);
@property (nonatomic, copy, nullable) void (^onEventFired)(NSString *eventType, NSDictionary<NSString *, id> *params);

- (void)play;
- (void)pause;
- (void)seekToTime:(NSTimeInterval)time;
- (void)stepFrame:(NSInteger)direction;
- (void)tick:(NSTimeInterval)delta;
- (void)syncToCurrentTime;

- (NSArray<NSDictionary<NSString *, id> *> *)activeHitboxPayloads;
- (NSArray<NSDictionary<NSString *, id> *> *)activeShaderPayloads;
- (nullable NSDictionary<NSString *, id> *)primaryActiveShaderPayload;
- (NSString *)resolvedAnimationNameAtCurrentTime;

@end

NS_ASSUME_NONNULL_END
