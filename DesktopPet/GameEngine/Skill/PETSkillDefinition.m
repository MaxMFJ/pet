#import "PETSkillDefinition.h"

#import "PETSkillPhase.h"

@interface PETSkillDefinition ()

@property (nonatomic, copy) NSString *skillIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *castType;
@property (nonatomic, copy) NSString *entryPhaseIdentifier;
@property (nonatomic, copy) NSArray<NSString *> *tags;
@property (nonatomic, copy) NSArray<PETSkillPhase *> *phases;
@property (nonatomic, assign) NSTimeInterval totalDuration;

@end

@implementation PETSkillDefinition

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *,id> *)dictionary {
    self = [super init];
    if (self) {
        NSString *skillIdentifier = [dictionary[@"skillId"] isKindOfClass:NSString.class] ? dictionary[@"skillId"] : @"skill";
        NSString *displayName = [dictionary[@"displayName"] isKindOfClass:NSString.class] ? dictionary[@"displayName"] : skillIdentifier;
        NSString *castType = [dictionary[@"castType"] isKindOfClass:NSString.class] ? dictionary[@"castType"] : @"skill";
        NSString *entryPhaseIdentifier = [dictionary[@"entryPhase"] isKindOfClass:NSString.class] ? dictionary[@"entryPhase"] : @"";
        NSArray<NSString *> *tags = [dictionary[@"tags"] isKindOfClass:NSArray.class] ? dictionary[@"tags"] : @[];
        NSArray<NSDictionary<NSString *, id> *> *rawPhases = [dictionary[@"phases"] isKindOfClass:NSArray.class] ? dictionary[@"phases"] : @[];

        NSMutableArray<PETSkillPhase *> *phases = [NSMutableArray arrayWithCapacity:rawPhases.count];
        NSTimeInterval totalDuration = 0.0;
        for (NSDictionary<NSString *, id> *rawPhase in rawPhases) {
            if (![rawPhase isKindOfClass:NSDictionary.class]) {
                continue;
            }
            PETSkillPhase *phase = [[PETSkillPhase alloc] initWithDictionaryRepresentation:rawPhase];
            [phases addObject:phase];
            totalDuration = MAX(totalDuration, phase.startTime + phase.duration);
        }

        _skillIdentifier = [skillIdentifier copy];
        _displayName = [displayName copy];
        _castType = [castType copy];
        _entryPhaseIdentifier = [entryPhaseIdentifier copy];
        _tags = [tags copy];
        _phases = [phases copy];
        _totalDuration = totalDuration;
    }
    return self;
}

- (nullable PETSkillPhase *)phaseWithIdentifier:(NSString *)phaseIdentifier {
    if (phaseIdentifier.length == 0) {
        return nil;
    }
    for (PETSkillPhase *phase in self.phases) {
        if ([phase.phaseIdentifier isEqualToString:phaseIdentifier]) {
            return phase;
        }
    }
    return nil;
}

- (PETSkillPhase *)entryPhase {
    PETSkillPhase *entryPhase = [self phaseWithIdentifier:self.entryPhaseIdentifier];
    return entryPhase ?: self.phases.firstObject;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    NSMutableArray<NSDictionary<NSString *, id> *> *phases = [NSMutableArray arrayWithCapacity:self.phases.count];
    for (PETSkillPhase *phase in self.phases) {
        [phases addObject:[phase dictionaryRepresentation]];
    }
    return @{
        @"skillId": self.skillIdentifier ?: @"skill",
        @"displayName": self.displayName ?: self.skillIdentifier ?: @"skill",
        @"castType": self.castType ?: @"skill",
        @"entryPhase": self.entryPhaseIdentifier ?: @"",
        @"tags": self.tags ?: @[],
        @"phases": phases.copy
    };
}

@end
