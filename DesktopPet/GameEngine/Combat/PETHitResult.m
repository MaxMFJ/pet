#import "PETHitResult.h"

@implementation PETHitResult

- (instancetype)initWithSourcePetIdentifier:(NSString *)sourcePetIdentifier
                        targetPetIdentifier:(NSString *)targetPetIdentifier
                           attackIdentifier:(NSString *)attackIdentifier
                                 attackKind:(NSString *)attackKind
                            hitStunDuration:(NSTimeInterval)hitStunDuration
                         knockdownDuration:(NSTimeInterval)knockdownDuration
                               launchVector:(CGVector)launchVector
                                combatState:(NSString *)combatState
                           causesKnockdown:(BOOL)causesKnockdown
                          collisionSnapshot:(NSDictionary<NSString *,id> *)collisionSnapshot {
    self = [super init];
    if (self) {
        _hitIdentifier = [NSUUID.UUID.UUIDString copy];
        _sourcePetIdentifier = [sourcePetIdentifier copy] ?: @"";
        _targetPetIdentifier = [targetPetIdentifier copy] ?: @"";
        _attackIdentifier = [attackIdentifier copy] ?: @"";
        _attackKind = [attackKind copy] ?: @"";
        _timestamp = NSDate.date;
        _hitStunDuration = MAX(0.0, hitStunDuration);
        _knockdownDuration = MAX(0.0, knockdownDuration);
        _launchVector = launchVector;
        _combatState = [combatState copy];
        _causesKnockdown = causesKnockdown;
        _collisionSnapshot = [collisionSnapshot copy] ?: @{};
    }
    return self;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    return @{
        @"hitIdentifier": self.hitIdentifier ?: @"",
        @"sourcePetIdentifier": self.sourcePetIdentifier ?: @"",
        @"targetPetIdentifier": self.targetPetIdentifier ?: @"",
        @"attackIdentifier": self.attackIdentifier ?: @"",
        @"attackKind": self.attackKind ?: @"",
        @"timestamp": @([self.timestamp timeIntervalSince1970]),
        @"hitStunDuration": @(self.hitStunDuration),
        @"knockdownDuration": @(self.knockdownDuration),
        @"launchVector": @{@"dx": @(self.launchVector.dx), @"dy": @(self.launchVector.dy)},
        @"combatState": self.combatState ?: @"",
        @"causesKnockdown": @(self.causesKnockdown),
        @"collisionSnapshot": self.collisionSnapshot ?: @{}
    };
}

@end
