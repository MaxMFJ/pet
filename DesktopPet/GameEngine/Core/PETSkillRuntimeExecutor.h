#import <Foundation/Foundation.h>

@class PETActiveSkillInstance;
@class PETGameEvent;
@class PETHitResult;
@class PETTargetMotionRuntime;

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, id> * _Nonnull (^PETCombatDebugSnapshotProvider)(void);

@interface PETSkillRuntimeAdvanceResult : NSObject

@property (nonatomic, copy, readonly) NSArray<PETGameEvent *> *events;
@property (nonatomic, copy, readonly) NSArray<PETGameEvent *> *pendingEffectEvents;
@property (nonatomic, copy, readonly) NSArray<PETHitResult *> *pendingEffectHitResults;
@property (nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *pendingMotionDirectives;
@property (nonatomic, assign, readonly) BOOL didChangePhase;
@property (nonatomic, assign, readonly) BOOL didFinishSkill;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *finalSkillSnapshot;

- (instancetype)initWithEvents:(NSArray<PETGameEvent *> *)events
           pendingEffectEvents:(NSArray<PETGameEvent *> *)pendingEffectEvents
        pendingEffectHitResults:(NSArray<PETHitResult *> *)pendingEffectHitResults
         pendingMotionDirectives:(NSArray<NSDictionary<NSString *, id> *> *)pendingMotionDirectives
                 didChangePhase:(BOOL)didChangePhase
                 didFinishSkill:(BOOL)didFinishSkill
             finalSkillSnapshot:(nullable NSDictionary<NSString *, id> *)finalSkillSnapshot NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface PETSkillRuntimeExecutor : NSObject

- (instancetype)initWithPetIdentifier:(NSString *)petIdentifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (PETSkillRuntimeAdvanceResult *)advanceSkillInstance:(PETActiveSkillInstance *)activeSkillInstance
                                             deltaTime:(NSTimeInterval)deltaTime
                                         motionRuntime:(PETTargetMotionRuntime *)motionRuntime
                             combatDebugSnapshotProvider:(PETCombatDebugSnapshotProvider)combatDebugSnapshotProvider;
- (nullable PETGameEvent *)eventForExecutedEffect:(NSDictionary<NSString *, id> *)effect
                                          phaseId:(NSString *)phaseIdentifier
                                 targetIdentifier:(nullable NSString *)targetIdentifier
                                    skillInstance:(PETActiveSkillInstance *)activeSkillInstance
                                     effectSource:(NSString *)effectSource;
- (nullable PETHitResult *)hitResultForSkillEffect:(NSDictionary<NSString *, id> *)effect
                                  targetIdentifier:(NSString *)targetIdentifier
                                           phaseId:(NSString *)phaseIdentifier
                                       skillInstance:(PETActiveSkillInstance *)activeSkillInstance
                                       effectIndex:(NSUInteger)effectIndex;
- (NSDictionary<NSString *, id> *)motionDirectiveForSkillEffect:(NSDictionary<NSString *, id> *)effect
                                               targetIdentifier:(NSString *)targetIdentifier
                                                        phaseId:(NSString *)phaseIdentifier
                                                  skillInstance:(PETActiveSkillInstance *)activeSkillInstance;

@end

NS_ASSUME_NONNULL_END
