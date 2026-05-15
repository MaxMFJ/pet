#import "PETStructuredCognitionSuggestion.h"

@implementation PETStructuredCognitionSuggestion

- (instancetype)initWithActionKey:(NSString *)actionKey
                          summary:(NSString *)summary
                         goalHint:(NSString *)goalHint
                       confidence:(double)confidence
                          context:(NSDictionary<NSString *,id> *)context {
    self = [super init];
    if (self) {
        _actionKey = [actionKey copy];
        _summary = [summary copy];
        _goalHint = [goalHint copy] ?: @"";
        _confidence = confidence;
        _context = [context copy] ?: @{};
    }
    return self;
}

+ (instancetype)suggestionFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *actionKey = [dictionary[@"actionKey"] isKindOfClass:NSString.class] ? dictionary[@"actionKey"] : nil;
    NSString *summary = [dictionary[@"summary"] isKindOfClass:NSString.class] ? dictionary[@"summary"] : nil;
    if (actionKey.length == 0 || summary.length == 0) {
        return nil;
    }
    NSString *goalHint = [dictionary[@"goalHint"] isKindOfClass:NSString.class] ? dictionary[@"goalHint"] : @"";
    double confidence = [dictionary[@"confidence"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"confidence"] doubleValue] : 0.0;
    NSDictionary<NSString *, id> *context = [dictionary[@"context"] isKindOfClass:NSDictionary.class] ? dictionary[@"context"] : @{};
    return [[self alloc] initWithActionKey:actionKey
                                   summary:summary
                                  goalHint:goalHint
                                confidence:confidence
                                   context:context];
}

- (NSDictionary<NSString *,id> *)serializedRepresentation {
    return @{
        @"actionKey": self.actionKey ?: @"cognition.observe",
        @"summary": self.summary ?: @"structured-cognition",
        @"goalHint": self.goalHint ?: @"",
        @"confidence": @(self.confidence),
        @"context": self.context ?: @{}
    };
}

@end
