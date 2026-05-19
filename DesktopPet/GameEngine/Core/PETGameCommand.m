#import "PETGameCommand.h"

NSString * const PETGameCommandMovePressed = @"move.pressed";
NSString * const PETGameCommandMoveReleased = @"move.released";
NSString * const PETGameCommandJumpPressed = @"jump.pressed";
NSString * const PETGameCommandJumpReleased = @"jump.released";
NSString * const PETGameCommandAttackPrimary = @"attack.primary";
NSString * const PETGameCommandAttackSecondary = @"attack.secondary";
NSString * const PETGameCommandSkillCast = @"skill.cast";
NSString * const PETGameCommandSkillCancel = @"skill.cancel";
NSString * const PETGameCommandUltimateCast = @"ultimate.cast";
NSString * const PETGameCommandPause = @"game.pause";
NSString * const PETGameCommandResume = @"game.resume";

NSString * const PETGameDirectionUp = @"up";
NSString * const PETGameDirectionDown = @"down";
NSString * const PETGameDirectionLeft = @"left";
NSString * const PETGameDirectionRight = @"right";

NSString * const PETGameCommandSourceKeyboard = @"keyboard";
NSString * const PETGameCommandSourceMouse = @"mouse";
NSString * const PETGameCommandSourceTouch = @"touch";
NSString * const PETGameCommandSourceRuntime = @"runtime";
NSString * const PETGameCommandSourceDebug = @"debug";

@implementation PETGameCommand

- (instancetype)initWithPetIdentifier:(NSString *)petIdentifier
                           commandType:(NSString *)commandType
                                source:(NSString *)source
                             direction:(NSString *)direction
                       skillIdentifier:(NSString *)skillIdentifier
                              strength:(double)strength
                               context:(NSDictionary<NSString *,id> *)context {
    self = [super init];
    if (self) {
        _commandIdentifier = [NSUUID.UUID.UUIDString copy];
        _petIdentifier = [petIdentifier copy] ?: @"";
        _commandType = [commandType copy] ?: @"debug";
        _source = [source copy] ?: PETGameCommandSourceDebug;
        _direction = [direction copy];
        _skillIdentifier = [skillIdentifier copy];
        _strength = strength;
        _timestamp = NSDate.date;
        _context = [context copy] ?: @{};
    }
    return self;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    NSMutableDictionary<NSString *, id> *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"commandId"] = self.commandIdentifier ?: @"";
    dictionary[@"petId"] = self.petIdentifier ?: @"";
    dictionary[@"type"] = self.commandType ?: @"";
    dictionary[@"source"] = self.source ?: @"";
    dictionary[@"strength"] = @(self.strength);
    dictionary[@"timestamp"] = @([self.timestamp timeIntervalSince1970]);
    dictionary[@"context"] = self.context ?: @{};
    if (self.direction.length > 0) {
        dictionary[@"direction"] = self.direction;
    }
    if (self.skillIdentifier.length > 0) {
        dictionary[@"skillId"] = self.skillIdentifier;
    }
    return dictionary.copy;
}

@end
