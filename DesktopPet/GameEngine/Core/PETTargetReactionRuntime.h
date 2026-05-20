#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETCombatStateComponent;
@class PETHitResult;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PETReactionStateNone;
FOUNDATION_EXPORT NSString * const PETReactionStateHitStun;
FOUNDATION_EXPORT NSString * const PETReactionStateLaunched;
FOUNDATION_EXPORT NSString * const PETReactionStateAirHold;
FOUNDATION_EXPORT NSString * const PETReactionStateKnockdown;
FOUNDATION_EXPORT NSString * const PETReactionStateGrabbed;

@interface PETTargetReactionRuntime : NSObject

@property (nonatomic, copy, readonly) NSString *currentReactionState;
@property (nonatomic, copy, readonly, nullable) NSString *currentReactionAnimationState;
@property (nonatomic, copy, readonly, nullable) NSString *lastReactionIdentifier;
@property (nonatomic, assign, readonly) NSTimeInterval reactionTimeRemaining;
@property (nonatomic, assign, readonly) CGFloat currentGravityScale;
@property (nonatomic, assign, readonly) BOOL locksHorizontalMotion;
@property (nonatomic, assign, readonly) BOOL locksVerticalMotion;

- (BOOL)applyHitResult:(PETHitResult *)hitResult
 toCombatStateComponent:(PETCombatStateComponent *)combatStateComponent;
- (void)syncWithCombatStateComponent:(PETCombatStateComponent *)combatStateComponent;
- (NSDictionary<NSString *, id> *)serializedState;
- (void)restoreFromSerializedState:(NSDictionary<NSString *, id> *)state;
- (NSDictionary<NSString *, id> *)debugSnapshot;

@end

NS_ASSUME_NONNULL_END
