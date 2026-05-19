#import <Foundation/Foundation.h>

@class PETCharacterRuntimeController;
@class PETAttackDefinition;
@class PETActiveSkillInstance;
@class PETCombatStateComponent;
@class PETGameCommand;
@class PETGameEvent;
@class PETPetProfile;
@class PETHitResult;
@class PETSkillLibrary;

NS_ASSUME_NONNULL_BEGIN

@interface PETGameSession : NSObject

@property (nonatomic, copy, readonly) NSString *petIdentifier;
@property (nonatomic, strong, readonly) PETPetProfile *profile;
@property (nonatomic, weak, readonly, nullable) PETCharacterRuntimeController *runtimeController;
@property (nonatomic, assign, readonly, getter=isPaused) BOOL paused;
@property (nonatomic, assign, readonly) NSUInteger tickCount;
@property (nonatomic, strong, readonly, nullable) NSDate *lastTickDate;
@property (nonatomic, strong, readonly) PETCombatStateComponent *combatStateComponent;
@property (nonatomic, strong, readonly, nullable) PETAttackDefinition *activeAttackDefinition;
@property (nonatomic, strong, readonly, nullable) PETActiveSkillInstance *activeSkillInstance;

- (instancetype)initWithProfile:(PETPetProfile *)profile
              runtimeController:(nullable PETCharacterRuntimeController *)runtimeController
                   skillLibrary:(nullable PETSkillLibrary *)skillLibrary NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)submitCommand:(PETGameCommand *)command;
- (NSArray<PETGameEvent *> *)tickWithDeltaTime:(NSTimeInterval)deltaTime;
- (void)setMovementPosition:(CGPoint)position bodySize:(CGSize)bodySize;
- (NSDictionary<NSString *, id> *)serializedState;
- (void)restoreFromSerializedState:(NSDictionary<NSString *, id> *)state;
- (void)setPaused:(BOOL)paused reason:(nullable NSString *)reason;
- (NSArray<PETGameEvent *> *)applyResolvedHitResult:(PETHitResult *)hitResult;
- (NSDictionary<NSString *, id> *)combatDebugSnapshot;
- (NSArray<NSDictionary<NSString *, id> *> *)activeSkillHitWindows;
- (nullable NSDictionary<NSString *, id> *)reactionDefinitionForActiveSkillHitWindow:(NSDictionary<NSString *, id> *)hitWindow;
- (BOOL)activeSkillCanHitTargetIdentifier:(NSString *)targetIdentifier hitWindow:(NSDictionary<NSString *, id> *)hitWindow;
- (NSArray<PETGameEvent *> *)drainPendingSkillEffectEvents;
- (NSArray<PETHitResult *> *)drainPendingSkillEffectHitResults;
- (void)registerActiveSkillHitTargetIdentifier:(NSString *)targetIdentifier hitWindow:(NSDictionary<NSString *, id> *)hitWindow;
- (nullable PETHitResult *)hitResultForActiveSkillHitWindow:(NSDictionary<NSString *, id> *)hitWindow
                                        targetPetIdentifier:(NSString *)targetPetIdentifier
                                          collisionSnapshot:(NSDictionary<NSString *, id> *)collisionSnapshot;

@end

NS_ASSUME_NONNULL_END
