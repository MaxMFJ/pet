#import "PETGameEngine.h"

#import "../../Models/PETPetProfile.h"
#import "../../Services/PETCharacterRuntimeController.h"
#import "../Combat/PETHitResolver.h"
#import "../Combat/PETHitResult.h"
#import "../Skill/PETSkillLibrary.h"
#import "PETGameCommand.h"
#import "PETGameEvent.h"
#import "PETGameSession.h"
#import "PETGameTickDriver.h"

NSNotificationName const PETGameEngineDidEmitEventsNotification = @"PETGameEngineDidEmitEventsNotification";
NSString * const PETGameEngineEventsUserInfoKey = @"events";

@interface PETGameEngine () <PETGameTickDriverDelegate>

@property (nonatomic, strong) NSMutableDictionary<NSString *, PETGameSession *> *sessions;
@property (nonatomic, strong) PETGameTickDriver *tickDriver;
@property (nonatomic, strong) NSMutableArray<PETGameEvent *> *mutableRecentEvents;
@property (nonatomic, strong) PETHitResolver *hitResolver;
@property (nonatomic, strong, nullable) PETSkillLibrary *skillLibrary;

@end

@implementation PETGameEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessions = [NSMutableDictionary dictionary];
        _mutableRecentEvents = [NSMutableArray array];
        _tickDriver = [[PETGameTickDriver alloc] init];
        _tickDriver.delegate = self;
        _hitResolver = [[PETHitResolver alloc] init];
        NSError *skillLibraryError = nil;
        _skillLibrary = [[PETSkillLibrary alloc] initWithBundle:NSBundle.mainBundle error:&skillLibraryError];
        if (_skillLibrary == nil && skillLibraryError != nil) {
            NSLog(@"[DesktopPet] Failed to load skill library: %@", skillLibraryError.localizedDescription ?: @"unknown");
        }
    }
    return self;
}

- (BOOL)running {
    return self.tickDriver.isRunning;
}

- (NSArray<NSString *> *)registeredPetIdentifiers {
    return [[self.sessions allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray<PETGameEvent *> *)recentEvents {
    return self.mutableRecentEvents.copy;
}

- (void)registerPetWithProfile:(PETPetProfile *)profile
              runtimeController:(PETCharacterRuntimeController *)runtimeController {
    if (profile.identifier.length == 0) {
        return;
    }
    if (self.sessions[profile.identifier] != nil) {
        return;
    }

    PETGameSession *session = [[PETGameSession alloc] initWithProfile:profile
                                                    runtimeController:runtimeController
                                                         skillLibrary:self.skillLibrary];
    self.sessions[profile.identifier] = session;

    PETGameEvent *event = [[PETGameEvent alloc] initWithEventType:PETGameEventSessionRegistered
                                                    petIdentifier:profile.identifier
                                                           source:@"game.engine"
                                                          context:@{@"displayName": profile.displayName ?: @"Pet"}];
    [self emitEvents:@[event]];
    [self updateTickDriverState];
}

- (void)removePetWithIdentifier:(NSString *)petIdentifier {
    if (petIdentifier.length == 0 || self.sessions[petIdentifier] == nil) {
        return;
    }
    [self.sessions removeObjectForKey:petIdentifier];

    PETGameEvent *event = [[PETGameEvent alloc] initWithEventType:PETGameEventSessionRemoved
                                                    petIdentifier:petIdentifier
                                                           source:@"game.engine"
                                                          context:nil];
    [self emitEvents:@[event]];
    [self updateTickDriverState];
}

- (void)removeAllPets {
    NSArray<NSString *> *petIdentifiers = self.registeredPetIdentifiers;
    [self.sessions removeAllObjects];

    NSMutableArray<PETGameEvent *> *events = [NSMutableArray arrayWithCapacity:petIdentifiers.count];
    for (NSString *petIdentifier in petIdentifiers) {
        [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventSessionRemoved
                                                    petIdentifier:petIdentifier
                                                           source:@"game.engine"
                                                          context:nil]];
    }
    [self emitEvents:events.copy];
    [self updateTickDriverState];
}

- (void)submitCommand:(PETGameCommand *)command {
    PETGameSession *session = self.sessions[command.petIdentifier];
    if (session == nil) {
        PETGameEvent *event = [[PETGameEvent alloc] initWithEventType:PETGameEventCommandRejected
                                                        petIdentifier:command.petIdentifier ?: @""
                                                               source:@"game.engine"
                                                              context:@{@"reason": @"missingSession",
                                                                        @"command": [command dictionaryRepresentation]}];
        [self emitEvents:@[event]];
        return;
    }
    [session submitCommand:command];
}

- (void)setMovementPosition:(CGPoint)position bodySize:(CGSize)bodySize forPetIdentifier:(NSString *)petIdentifier {
    PETGameSession *session = self.sessions[petIdentifier];
    [session setMovementPosition:position bodySize:bodySize];
}

- (NSDictionary<NSString *,id> *)serializedStateForPetIdentifier:(NSString *)petIdentifier {
    return [self.sessions[petIdentifier] serializedState];
}

- (NSDictionary<NSString *,id> *)combatDebugSnapshotForPetIdentifier:(NSString *)petIdentifier {
    return [self.sessions[petIdentifier] combatDebugSnapshot];
}

- (void)restorePetIdentifier:(NSString *)petIdentifier fromState:(NSDictionary<NSString *,id> *)state {
    PETGameSession *session = self.sessions[petIdentifier];
    [session restoreFromSerializedState:state ?: @{}];
}

- (void)clearRecentEvents {
    [self.mutableRecentEvents removeAllObjects];
}

- (void)gameTickDriver:(PETGameTickDriver *)driver didTickWithDeltaTime:(NSTimeInterval)deltaTime {
    (void)driver;
    NSMutableArray<PETGameEvent *> *events = [NSMutableArray array];
    NSArray<PETGameSession *> *sessions = self.sessions.allValues.copy;
    for (PETGameSession *session in sessions) {
        [events addObjectsFromArray:[session tickWithDeltaTime:deltaTime]];
    }
    NSArray<PETHitResult *> *hitResults = [self.hitResolver resolveHitsForSessions:sessions
                                                                collisionEvaluator:^NSDictionary<NSString *,id> * _Nullable(NSString *sourcePetIdentifier, NSString *targetPetIdentifier, CGFloat sampleSpacing) {
        if (self.pixelCollisionEvaluator == nil) {
            return nil;
        }
        return self.pixelCollisionEvaluator(sourcePetIdentifier, targetPetIdentifier, sampleSpacing);
    }];
    for (PETHitResult *hitResult in hitResults) {
        [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventAttackHit
                                                    petIdentifier:hitResult.sourcePetIdentifier
                                                           source:@"game.combat"
                                                          context:[hitResult dictionaryRepresentation]]];
        PETGameSession *targetSession = self.sessions[hitResult.targetPetIdentifier];
        [events addObjectsFromArray:[targetSession applyResolvedHitResult:hitResult]];
    }
    for (PETGameSession *session in sessions) {
        [events addObjectsFromArray:[session drainPendingSkillEffectEvents]];
        NSArray<PETHitResult *> *effectHitResults = [session drainPendingSkillEffectHitResults];
        for (PETHitResult *hitResult in effectHitResults) {
            [events addObject:[[PETGameEvent alloc] initWithEventType:PETGameEventAttackHit
                                                        petIdentifier:hitResult.sourcePetIdentifier
                                                               source:@"game.skill.effect"
                                                              context:[hitResult dictionaryRepresentation]]];
            PETGameSession *targetSession = self.sessions[hitResult.targetPetIdentifier];
            [events addObjectsFromArray:[targetSession applyResolvedHitResult:hitResult]];
        }
    }
    for (PETGameSession *session in sessions) {
        NSArray<NSDictionary<NSString *, id> *> *motionDirectives = [session drainPendingSkillMotionDirectives];
        for (NSDictionary<NSString *, id> *directive in motionDirectives) {
            NSString *targetPetIdentifier = [directive[@"targetPetIdentifier"] isKindOfClass:NSString.class] ? directive[@"targetPetIdentifier"] : nil;
            NSString *sourcePetIdentifier = [directive[@"sourcePetIdentifier"] isKindOfClass:NSString.class] ? directive[@"sourcePetIdentifier"] : nil;
            PETGameSession *targetSession = self.sessions[targetPetIdentifier];
            PETGameSession *sourceSession = self.sessions[sourcePetIdentifier];
            if (targetSession == nil || sourceSession == nil) {
                continue;
            }
            [events addObjectsFromArray:[targetSession applyMotionDirective:directive
                                                             sourcePosition:[sourceSession movementPosition]
                                                           sourceFacingRight:[sourceSession isFacingRight]]];
        }
    }
    for (PETGameSession *session in sessions) {
        NSString *sourcePetIdentifier = [session activeConstraintSourcePetIdentifier];
        if (sourcePetIdentifier.length == 0) {
            continue;
        }
        PETGameSession *sourceSession = self.sessions[sourcePetIdentifier];
        if (sourceSession == nil) {
            continue;
        }
        [events addObjectsFromArray:[session syncConstraintFromSourcePosition:[sourceSession movementPosition]
                                                            sourceFacingRight:[sourceSession isFacingRight]]];
    }
    [self emitEvents:events.copy];
}

- (void)updateTickDriverState {
    if (self.sessions.count > 0) {
        [self.tickDriver start];
    } else {
        [self.tickDriver stop];
    }
}

- (void)emitEvents:(NSArray<PETGameEvent *> *)events {
    if (events.count == 0) {
        return;
    }
    [self.mutableRecentEvents addObjectsFromArray:events];
    static NSUInteger const PETGameEngineMaxRecentEventCount = 80;
    if (self.mutableRecentEvents.count > PETGameEngineMaxRecentEventCount) {
        NSRange overflowRange = NSMakeRange(0, self.mutableRecentEvents.count - PETGameEngineMaxRecentEventCount);
        [self.mutableRecentEvents removeObjectsInRange:overflowRange];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PETGameEngineDidEmitEventsNotification
                                                        object:self
                                                      userInfo:@{PETGameEngineEventsUserInfoKey: events}];
}

@end
