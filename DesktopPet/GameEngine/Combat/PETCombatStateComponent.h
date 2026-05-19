#import <Foundation/Foundation.h>

@class PETAttackDefinition;
@class PETHitResult;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PETCombatStateIdle;
FOUNDATION_EXPORT NSString * const PETCombatStateAttacking;
FOUNDATION_EXPORT NSString * const PETCombatStateHitStun;
FOUNDATION_EXPORT NSString * const PETCombatStateLaunched;
FOUNDATION_EXPORT NSString * const PETCombatStateKnockedDown;

@interface PETCombatStateComponent : NSObject

@property (nonatomic, copy, readonly) NSString *currentState;
@property (nonatomic, assign, readonly) NSTimeInterval stateTimeRemaining;
@property (nonatomic, assign, readonly, getter=isControlLocked) BOOL controlLocked;
@property (nonatomic, copy, readonly, nullable) NSString *currentAttackIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *lastHitIdentifier;

- (BOOL)beginAttackWithDefinition:(PETAttackDefinition *)attackDefinition;
- (BOOL)advanceTime:(NSTimeInterval)deltaTime;
- (BOOL)clearAttackIdentifierIfMatches:(NSString *)attackIdentifier;
- (BOOL)applyHitResult:(PETHitResult *)hitResult;
- (NSDictionary<NSString *, id> *)serializedState;
- (void)restoreFromSerializedState:(NSDictionary<NSString *, id> *)state;
- (NSDictionary<NSString *, id> *)debugSnapshot;

@end

NS_ASSUME_NONNULL_END
