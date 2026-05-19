#import "PETAttackDefinition.h"

#import "../Core/PETGameCommand.h"

NSString * const PETAttackKindPrimary = @"attack.primary";
NSString * const PETAttackKindSecondary = @"attack.secondary";
NSString * const PETAttackKindSkill = @"attack.skill";
NSString * const PETAttackKindUltimate = @"attack.ultimate";

@interface PETAttackDefinition ()

@property (nonatomic, copy) NSString *attackIdentifier;
@property (nonatomic, copy) NSString *sourcePetIdentifier;
@property (nonatomic, copy) NSString *attackKind;
@property (nonatomic, copy, nullable) NSString *skillIdentifier;
@property (nonatomic, assign) NSTimeInterval startupDuration;
@property (nonatomic, assign) NSTimeInterval activeDuration;
@property (nonatomic, assign) NSTimeInterval recoveryDuration;
@property (nonatomic, assign) NSTimeInterval hitStunDuration;
@property (nonatomic, assign) NSTimeInterval knockdownDuration;
@property (nonatomic, assign) CGVector launchVector;
@property (nonatomic, assign) BOOL causesKnockdown;
@property (nonatomic, assign, getter=isCollisionEnabled) BOOL collisionEnabled;
@property (nonatomic, assign) CGFloat sampleSpacing;
@property (nonatomic, assign) NSUInteger maxHitCountPerTarget;
@property (nonatomic, assign) NSTimeInterval elapsedTime;
@property (nonatomic, strong) NSMutableSet<NSString *> *mutableHitTargetIdentifiers;

@end

@implementation PETAttackDefinition

- (instancetype)initWithSourcePetIdentifier:(NSString *)sourcePetIdentifier
                                 attackKind:(NSString *)attackKind
                            skillIdentifier:(NSString *)skillIdentifier
                            startupDuration:(NSTimeInterval)startupDuration
                             activeDuration:(NSTimeInterval)activeDuration
                           recoveryDuration:(NSTimeInterval)recoveryDuration
                            hitStunDuration:(NSTimeInterval)hitStunDuration
                         knockdownDuration:(NSTimeInterval)knockdownDuration
                               launchVector:(CGVector)launchVector
                           causesKnockdown:(BOOL)causesKnockdown
                           collisionEnabled:(BOOL)collisionEnabled
                              sampleSpacing:(CGFloat)sampleSpacing
                       maxHitCountPerTarget:(NSUInteger)maxHitCountPerTarget {
    self = [super init];
    if (self) {
        _attackIdentifier = [NSUUID.UUID.UUIDString copy];
        _sourcePetIdentifier = [sourcePetIdentifier copy] ?: @"";
        _attackKind = [attackKind copy] ?: PETAttackKindPrimary;
        _skillIdentifier = [skillIdentifier copy];
        _startupDuration = MAX(0.0, startupDuration);
        _activeDuration = MAX(0.01, activeDuration);
        _recoveryDuration = MAX(0.0, recoveryDuration);
        _hitStunDuration = MAX(0.0, hitStunDuration);
        _knockdownDuration = MAX(0.0, knockdownDuration);
        _launchVector = launchVector;
        _causesKnockdown = causesKnockdown;
        _collisionEnabled = collisionEnabled;
        _sampleSpacing = MAX(1.0, sampleSpacing);
        _maxHitCountPerTarget = MAX((NSUInteger)1, maxHitCountPerTarget);
        _mutableHitTargetIdentifiers = [NSMutableSet set];
    }
    return self;
}

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *,id> *)dictionary {
    NSString *sourcePetIdentifier = [dictionary[@"sourcePetIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"sourcePetIdentifier"] : @"";
    NSString *attackKind = [dictionary[@"attackKind"] isKindOfClass:NSString.class] ? dictionary[@"attackKind"] : PETAttackKindPrimary;
    NSString *skillIdentifier = [dictionary[@"skillIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"skillIdentifier"] : nil;
    NSDictionary<NSString *, id> *launchVector = [dictionary[@"launchVector"] isKindOfClass:NSDictionary.class] ? dictionary[@"launchVector"] : nil;

    self = [self initWithSourcePetIdentifier:sourcePetIdentifier
                                  attackKind:attackKind
                             skillIdentifier:skillIdentifier
                             startupDuration:[dictionary[@"startupDuration"] doubleValue]
                              activeDuration:[dictionary[@"activeDuration"] doubleValue]
                            recoveryDuration:[dictionary[@"recoveryDuration"] doubleValue]
                             hitStunDuration:[dictionary[@"hitStunDuration"] doubleValue]
                          knockdownDuration:[dictionary[@"knockdownDuration"] doubleValue]
                                launchVector:CGVectorMake([launchVector[@"dx"] doubleValue], [launchVector[@"dy"] doubleValue])
                            causesKnockdown:[dictionary[@"causesKnockdown"] boolValue]
                           collisionEnabled:![dictionary[@"collisionEnabled"] respondsToSelector:@selector(boolValue)] || [dictionary[@"collisionEnabled"] boolValue]
                               sampleSpacing:[dictionary[@"sampleSpacing"] doubleValue]
                        maxHitCountPerTarget:[dictionary[@"maxHitCountPerTarget"] unsignedIntegerValue]];
    if (self) {
        NSString *attackIdentifier = [dictionary[@"attackIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"attackIdentifier"] : NSUUID.UUID.UUIDString;
        _attackIdentifier = [attackIdentifier copy];
        _elapsedTime = MAX(0.0, [dictionary[@"elapsedTime"] doubleValue]);
        NSArray<NSString *> *hitTargets = [dictionary[@"hitTargetIdentifiers"] isKindOfClass:NSArray.class] ? dictionary[@"hitTargetIdentifiers"] : @[];
        self.mutableHitTargetIdentifiers = [NSMutableSet setWithArray:hitTargets];
    }
    return self;
}

+ (instancetype)attackDefinitionForCommand:(PETGameCommand *)command {
    if (command.petIdentifier.length == 0) {
        return nil;
    }

    NSString *attackKind = nil;
    NSTimeInterval startupDuration = 0.0;
    NSTimeInterval activeDuration = 0.0;
    NSTimeInterval recoveryDuration = 0.0;
    NSTimeInterval hitStunDuration = 0.0;
    NSTimeInterval knockdownDuration = 0.0;
    CGVector launchVector = CGVectorMake(0.0, 0.0);
    BOOL causesKnockdown = NO;

    if ([command.commandType isEqualToString:PETGameCommandAttackPrimary]) {
        attackKind = PETAttackKindPrimary;
        startupDuration = 0.08;
        activeDuration = 0.10;
        recoveryDuration = 0.18;
        hitStunDuration = 0.22;
        launchVector = CGVectorMake(100.0, 40.0);
    } else if ([command.commandType isEqualToString:PETGameCommandAttackSecondary]) {
        attackKind = PETAttackKindSecondary;
        startupDuration = 0.14;
        activeDuration = 0.12;
        recoveryDuration = 0.24;
        hitStunDuration = 0.32;
        launchVector = CGVectorMake(140.0, 90.0);
    } else if ([command.commandType isEqualToString:PETGameCommandSkillCast]) {
        attackKind = PETAttackKindSkill;
        startupDuration = 0.20;
        activeDuration = 0.20;
        recoveryDuration = 0.30;
        hitStunDuration = 0.45;
        launchVector = CGVectorMake(180.0, 140.0);
    } else if ([command.commandType isEqualToString:PETGameCommandUltimateCast]) {
        attackKind = PETAttackKindUltimate;
        startupDuration = 0.28;
        activeDuration = 0.28;
        recoveryDuration = 0.40;
        hitStunDuration = 0.65;
        knockdownDuration = 0.80;
        launchVector = CGVectorMake(220.0, 180.0);
        causesKnockdown = YES;
    }

    if (attackKind.length == 0) {
        return nil;
    }

    return [[self alloc] initWithSourcePetIdentifier:command.petIdentifier
                                          attackKind:attackKind
                                     skillIdentifier:command.skillIdentifier
                                     startupDuration:startupDuration
                                      activeDuration:activeDuration
                                    recoveryDuration:recoveryDuration
                                     hitStunDuration:hitStunDuration
                                  knockdownDuration:knockdownDuration
                                        launchVector:launchVector
                                    causesKnockdown:causesKnockdown
                                   collisionEnabled:YES
                                       sampleSpacing:4.0
                                maxHitCountPerTarget:1];
}

- (NSSet<NSString *> *)hitTargetIdentifiers {
    return self.mutableHitTargetIdentifiers.copy;
}

- (BOOL)isActive {
    return self.elapsedTime >= self.startupDuration && !self.isFinished;
}

- (BOOL)isFinished {
    return self.elapsedTime >= (self.startupDuration + self.activeDuration + self.recoveryDuration);
}

- (void)advanceTime:(NSTimeInterval)deltaTime {
    self.elapsedTime += MAX(0.0, deltaTime);
}

- (BOOL)canHitTargetIdentifier:(NSString *)targetPetIdentifier {
    if (targetPetIdentifier.length == 0) {
        return NO;
    }
    return ![self.mutableHitTargetIdentifiers containsObject:targetPetIdentifier];
}

- (void)registerHitTargetIdentifier:(NSString *)targetPetIdentifier {
    if (targetPetIdentifier.length == 0) {
        return;
    }
    [self.mutableHitTargetIdentifiers addObject:targetPetIdentifier];
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    return @{
        @"attackIdentifier": self.attackIdentifier ?: @"",
        @"sourcePetIdentifier": self.sourcePetIdentifier ?: @"",
        @"attackKind": self.attackKind ?: @"",
        @"skillIdentifier": self.skillIdentifier ?: @"",
        @"startupDuration": @(self.startupDuration),
        @"activeDuration": @(self.activeDuration),
        @"recoveryDuration": @(self.recoveryDuration),
        @"hitStunDuration": @(self.hitStunDuration),
        @"knockdownDuration": @(self.knockdownDuration),
        @"launchVector": @{@"dx": @(self.launchVector.dx), @"dy": @(self.launchVector.dy)},
        @"causesKnockdown": @(self.causesKnockdown),
        @"collisionEnabled": @(self.isCollisionEnabled),
        @"sampleSpacing": @(self.sampleSpacing),
        @"maxHitCountPerTarget": @(self.maxHitCountPerTarget),
        @"elapsedTime": @(self.elapsedTime),
        @"hitTargetIdentifiers": self.hitTargetIdentifiers.allObjects ?: @[]
    };
}

@end
