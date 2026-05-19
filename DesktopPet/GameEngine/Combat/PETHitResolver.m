#import "PETHitResolver.h"

#import "../Core/PETGameSession.h"
#import "PETCombatStateComponent.h"
#import "PETAttackDefinition.h"
#import "PETHitResult.h"

@implementation PETHitResolver

- (NSArray<PETHitResult *> *)resolveHitsForSessions:(NSArray<PETGameSession *> *)sessions
                                 collisionEvaluator:(PETCombatCollisionEvaluator)collisionEvaluator {
    if (sessions.count <= 1 || collisionEvaluator == nil) {
        return @[];
    }

    NSMutableArray<PETHitResult *> *hitResults = [NSMutableArray array];
    for (PETGameSession *attacker in sessions) {
        PETAttackDefinition *attackDefinition = attacker.activeAttackDefinition;
        if (attackDefinition != nil && attackDefinition.isCollisionEnabled && attackDefinition.isActive && !attackDefinition.isFinished) {
            for (PETGameSession *target in sessions) {
                if (target == attacker) {
                    continue;
                }
                if (![attackDefinition canHitTargetIdentifier:target.petIdentifier]) {
                    continue;
                }

                NSDictionary<NSString *, id> *collisionSnapshot = collisionEvaluator(attacker.petIdentifier,
                                                                                     target.petIdentifier,
                                                                                     attackDefinition.sampleSpacing);
                if (collisionSnapshot.count == 0) {
                    continue;
                }

                [attackDefinition registerHitTargetIdentifier:target.petIdentifier];
                PETHitResult *hitResult = [[PETHitResult alloc] initWithSourcePetIdentifier:attacker.petIdentifier
                                                                          targetPetIdentifier:target.petIdentifier
                                                                             attackIdentifier:attackDefinition.attackIdentifier
                                                                                   attackKind:attackDefinition.attackKind
                                                                              hitStunDuration:attackDefinition.hitStunDuration
                                                                           knockdownDuration:attackDefinition.knockdownDuration
                                                                                 launchVector:attackDefinition.launchVector
                                                                                  combatState:(attackDefinition.causesKnockdown
                                                                                               ? PETCombatStateKnockedDown
                                                                                               : (fabs(attackDefinition.launchVector.dy) > 1.0
                                                                                                  ? PETCombatStateLaunched
                                                                                                  : PETCombatStateHitStun))
                                                                             causesKnockdown:attackDefinition.causesKnockdown
                                                                            collisionSnapshot:collisionSnapshot];
                [hitResults addObject:hitResult];
            }
        }

        for (NSDictionary<NSString *, id> *hitWindow in [attacker activeSkillHitWindows]) {
            CGFloat sampleSpacing = MAX(1.0, [hitWindow[@"sampleSpacing"] doubleValue]);
            for (PETGameSession *target in sessions) {
                if (target == attacker) {
                    continue;
                }
                if (![attacker activeSkillCanHitTargetIdentifier:target.petIdentifier hitWindow:hitWindow]) {
                    continue;
                }

                NSDictionary<NSString *, id> *collisionSnapshot = collisionEvaluator(attacker.petIdentifier,
                                                                                     target.petIdentifier,
                                                                                     sampleSpacing);
                if (collisionSnapshot.count == 0) {
                    continue;
                }

                [attacker registerActiveSkillHitTargetIdentifier:target.petIdentifier hitWindow:hitWindow];
                PETHitResult *hitResult = [attacker hitResultForActiveSkillHitWindow:hitWindow
                                                                  targetPetIdentifier:target.petIdentifier
                                                                    collisionSnapshot:collisionSnapshot];
                if (hitResult != nil) {
                    [hitResults addObject:hitResult];
                }
            }
        }
    }
    return hitResults.copy;
}

@end
