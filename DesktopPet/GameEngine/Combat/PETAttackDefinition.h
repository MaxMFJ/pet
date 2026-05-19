#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETGameCommand;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PETAttackKindPrimary;
FOUNDATION_EXPORT NSString * const PETAttackKindSecondary;
FOUNDATION_EXPORT NSString * const PETAttackKindSkill;
FOUNDATION_EXPORT NSString * const PETAttackKindUltimate;

@interface PETAttackDefinition : NSObject

@property (nonatomic, copy, readonly) NSString *attackIdentifier;
@property (nonatomic, copy, readonly) NSString *sourcePetIdentifier;
@property (nonatomic, copy, readonly) NSString *attackKind;
@property (nonatomic, copy, readonly, nullable) NSString *skillIdentifier;
@property (nonatomic, assign, readonly) NSTimeInterval startupDuration;
@property (nonatomic, assign, readonly) NSTimeInterval activeDuration;
@property (nonatomic, assign, readonly) NSTimeInterval recoveryDuration;
@property (nonatomic, assign, readonly) NSTimeInterval hitStunDuration;
@property (nonatomic, assign, readonly) NSTimeInterval knockdownDuration;
@property (nonatomic, assign, readonly) CGVector launchVector;
@property (nonatomic, assign, readonly) BOOL causesKnockdown;
@property (nonatomic, assign, readonly, getter=isCollisionEnabled) BOOL collisionEnabled;
@property (nonatomic, assign, readonly) CGFloat sampleSpacing;
@property (nonatomic, assign, readonly) NSUInteger maxHitCountPerTarget;
@property (nonatomic, assign, readonly) NSTimeInterval elapsedTime;
@property (nonatomic, assign, readonly, getter=isActive) BOOL active;
@property (nonatomic, assign, readonly, getter=isFinished) BOOL finished;
@property (nonatomic, copy, readonly) NSSet<NSString *> *hitTargetIdentifiers;

- (instancetype)initWithSourcePetIdentifier:(NSString *)sourcePetIdentifier
                                 attackKind:(NSString *)attackKind
                            skillIdentifier:(nullable NSString *)skillIdentifier
                            startupDuration:(NSTimeInterval)startupDuration
                             activeDuration:(NSTimeInterval)activeDuration
                           recoveryDuration:(NSTimeInterval)recoveryDuration
                            hitStunDuration:(NSTimeInterval)hitStunDuration
                         knockdownDuration:(NSTimeInterval)knockdownDuration
                               launchVector:(CGVector)launchVector
                           causesKnockdown:(BOOL)causesKnockdown
                           collisionEnabled:(BOOL)collisionEnabled
                              sampleSpacing:(CGFloat)sampleSpacing
                       maxHitCountPerTarget:(NSUInteger)maxHitCountPerTarget NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *, id> *)dictionary;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (nullable instancetype)attackDefinitionForCommand:(PETGameCommand *)command;
- (void)advanceTime:(NSTimeInterval)deltaTime;
- (BOOL)canHitTargetIdentifier:(NSString *)targetPetIdentifier;
- (void)registerHitTargetIdentifier:(NSString *)targetPetIdentifier;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
