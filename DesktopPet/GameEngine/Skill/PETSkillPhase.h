#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillPhase : NSObject

@property (nonatomic, copy, readonly) NSString *phaseIdentifier;
@property (nonatomic, assign, readonly) NSTimeInterval startTime;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, copy, readonly) NSString *animationState;
@property (nonatomic, assign, readonly) BOOL movementLock;
@property (nonatomic, assign, readonly) CGFloat gravityScale;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *casterMotion;
@property (nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *hitWindows;
@property (nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *effects;
@property (nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *transitions;

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *, id> *)dictionary NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
- (NSArray<NSDictionary<NSString *, id> *> *)activeHitWindowsAtPhaseTime:(NSTimeInterval)phaseTime;
- (CGVector)casterMotionOffsetAtPhaseTime:(NSTimeInterval)phaseTime facingRight:(BOOL)facingRight;

@end

NS_ASSUME_NONNULL_END
