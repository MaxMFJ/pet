#import <Foundation/Foundation.h>

@class PETSkillDefinition;
@class PETSkillPhase;

NS_ASSUME_NONNULL_BEGIN

@interface PETActiveSkillInstance : NSObject

@property (nonatomic, copy, readonly) NSString *instanceIdentifier;
@property (nonatomic, copy, readonly) NSString *casterPetIdentifier;
@property (nonatomic, strong, readonly) PETSkillDefinition *skillDefinition;
@property (nonatomic, strong, readonly, nullable) PETSkillPhase *currentPhase;
@property (nonatomic, assign, readonly) NSTimeInterval elapsedTime;
@property (nonatomic, assign, readonly) NSTimeInterval phaseElapsedTime;
@property (nonatomic, assign, readonly, getter=isFinished) BOOL finished;
@property (nonatomic, copy, readonly, nullable) NSString *lastHitTargetIdentifier;

- (instancetype)initWithSkillDefinition:(PETSkillDefinition *)skillDefinition
                    casterPetIdentifier:(NSString *)casterPetIdentifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)advanceTime:(NSTimeInterval)deltaTime;
- (BOOL)transitionToPhaseIdentifier:(NSString *)phaseIdentifier;
- (NSArray<NSDictionary<NSString *, id> *> *)activeHitWindows;
- (NSArray<NSDictionary<NSString *, id> *> *)currentPhaseEffects;
- (NSArray<NSDictionary<NSString *, id> *> *)currentPhaseTransitions;
- (NSArray<NSDictionary<NSString *, id> *> *)timedEffectsTriggeredFromPhase:(nullable PETSkillPhase *)fromPhase
                                                                   fromTime:(NSTimeInterval)fromTime
                                                                    toPhase:(nullable PETSkillPhase *)toPhase
                                                                     toTime:(NSTimeInterval)toTime;
- (void)registerSpawnedProjectileIdentifier:(NSString *)projectileIdentifier;
- (BOOL)hasActiveProjectileIdentifier:(NSString *)projectileIdentifier;
- (BOOL)registerReturnedProjectileIdentifier:(NSString *)projectileIdentifier;
- (BOOL)handleProjectileReturnIdentifier:(NSString *)projectileIdentifier;
- (BOOL)shouldExecuteHitEffect:(NSDictionary<NSString *, id> *)effect
               targetIdentifier:(NSString *)targetIdentifier
                          phase:(nullable PETSkillPhase *)phase
                    effectIndex:(NSUInteger)effectIndex;
- (void)registerExecutedHitEffect:(NSDictionary<NSString *, id> *)effect
                 targetIdentifier:(NSString *)targetIdentifier
                            phase:(nullable PETSkillPhase *)phase
                      effectIndex:(NSUInteger)effectIndex;
- (BOOL)canHitTargetIdentifier:(NSString *)targetIdentifier forHitWindow:(NSDictionary<NSString *, id> *)hitWindow;
- (void)registerHitTargetIdentifier:(NSString *)targetIdentifier forHitWindow:(NSDictionary<NSString *, id> *)hitWindow;
- (BOOL)handleHitForWindowIdentifier:(NSString *)windowIdentifier targetIdentifier:(NSString *)targetIdentifier;
- (NSDictionary<NSString *, id> *)debugSnapshot;

@end

NS_ASSUME_NONNULL_END
