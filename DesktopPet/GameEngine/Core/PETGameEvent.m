#import "PETGameEvent.h"

NSString * const PETGameEventSessionRegistered = @"game.session.registered";
NSString * const PETGameEventSessionRemoved = @"game.session.removed";
NSString * const PETGameEventCommandAccepted = @"game.command.accepted";
NSString * const PETGameEventCommandRejected = @"game.command.rejected";
NSString * const PETGameEventTick = @"game.tick";
NSString * const PETGameEventCombatStateChanged = @"game.combat.state.changed";
NSString * const PETGameEventAttackStarted = @"game.attack.started";
NSString * const PETGameEventAttackEnded = @"game.attack.ended";
NSString * const PETGameEventAttackHit = @"game.attack.hit";

@implementation PETGameEvent

- (instancetype)initWithEventType:(NSString *)eventType
                     petIdentifier:(NSString *)petIdentifier
                            source:(NSString *)source
                           context:(NSDictionary<NSString *,id> *)context {
    self = [super init];
    if (self) {
        _eventIdentifier = [NSUUID.UUID.UUIDString copy];
        _eventType = [eventType copy] ?: PETGameEventTick;
        _petIdentifier = [petIdentifier copy] ?: @"";
        _source = [source copy] ?: @"game.engine";
        _timestamp = NSDate.date;
        _context = [context copy] ?: @{};
    }
    return self;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    return @{
        @"eventId": self.eventIdentifier ?: @"",
        @"eventType": self.eventType ?: @"",
        @"petId": self.petIdentifier ?: @"",
        @"source": self.source ?: @"",
        @"timestamp": @([self.timestamp timeIntervalSince1970]),
        @"context": self.context ?: @{}
    };
}

@end
