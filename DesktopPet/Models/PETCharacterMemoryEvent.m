#import "PETCharacterMemoryEvent.h"

@implementation PETCharacterMemoryEvent

- (instancetype)initWithEventIdentifier:(NSString *)eventIdentifier
                              eventType:(NSString *)eventType
                                summary:(NSString *)summary
                               salience:(NSInteger)salience
                               metadata:(NSDictionary<NSString *,id> *)metadata
                              timestamp:(NSDate *)timestamp {
    self = [super init];
    if (self) {
        _eventIdentifier = [eventIdentifier copy];
        _eventType = [eventType copy];
        _summary = [summary copy];
        _salience = salience;
        _metadata = [metadata copy] ?: @{};
        _timestamp = timestamp ?: [NSDate date];
    }
    return self;
}

- (NSDictionary<NSString *,id> *)serializedRepresentation {
    return @{
        @"eventIdentifier": self.eventIdentifier ?: @"memory",
        @"eventType": self.eventType ?: @"runtime",
        @"summary": self.summary ?: @"memory",
        @"salience": @(self.salience),
        @"metadata": self.metadata ?: @{},
        @"timestamp": @([self.timestamp timeIntervalSince1970])
    };
}

+ (instancetype)eventFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *eventIdentifier = [dictionary[@"eventIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"eventIdentifier"] : nil;
    NSString *eventType = [dictionary[@"eventType"] isKindOfClass:NSString.class] ? dictionary[@"eventType"] : nil;
    NSString *summary = [dictionary[@"summary"] isKindOfClass:NSString.class] ? dictionary[@"summary"] : nil;
    if (eventIdentifier.length == 0 || eventType.length == 0 || summary.length == 0) {
        return nil;
    }
    NSInteger salience = [dictionary[@"salience"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"salience"] integerValue] : 0;
    NSDictionary<NSString *, id> *metadata = [dictionary[@"metadata"] isKindOfClass:NSDictionary.class] ? dictionary[@"metadata"] : @{};
    NSTimeInterval timestampValue = [dictionary[@"timestamp"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"timestamp"] doubleValue] : [[NSDate date] timeIntervalSince1970];
    NSDate *timestamp = [NSDate dateWithTimeIntervalSince1970:timestampValue];
    return [[self alloc] initWithEventIdentifier:eventIdentifier
                                       eventType:eventType
                                         summary:summary
                                        salience:salience
                                        metadata:metadata
                                       timestamp:timestamp];
}

@end
