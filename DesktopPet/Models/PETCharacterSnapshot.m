#import "PETCharacterSnapshot.h"

static NSString * const PETCharacterSnapshotSchemaVersion = @"1";

@implementation PETCharacterSnapshot

- (instancetype)initWithIntentName:(NSString *)intentName
                      intentSource:(NSString *)intentSource
                  intentConfidence:(double)intentConfidence
                      emotionLabel:(NSString *)emotionLabel
                    emotionValence:(double)emotionValence
                    emotionArousal:(double)emotionArousal
                     behaviorState:(NSString *)behaviorState
                      behaviorMode:(NSString *)behaviorMode
                    behaviorReason:(NSString *)behaviorReason
                    animationState:(NSString *)animationState
                           context:(NSDictionary<NSString *,id> *)context
                         timestamp:(NSDate *)timestamp {
    self = [super init];
    if (self) {
        _schemaVersion = PETCharacterSnapshotSchemaVersion;
        _intentName = [intentName copy];
        _intentSource = [intentSource copy];
        _intentConfidence = intentConfidence;
        _emotionLabel = [emotionLabel copy];
        _emotionValence = emotionValence;
        _emotionArousal = emotionArousal;
        _behaviorState = [behaviorState copy];
        _behaviorMode = [behaviorMode copy];
        _behaviorReason = [behaviorReason copy];
        _animationState = [animationState copy];
        _context = [context copy] ?: @{};
        _timestamp = timestamp ?: [NSDate date];
    }
    return self;
}

- (NSDictionary<NSString *, id> *)serializedRepresentation {
    return @{
        @"schemaVersion": self.schemaVersion ?: PETCharacterSnapshotSchemaVersion,
        @"intentName": self.intentName ?: @"ambient.exist",
        @"intentSource": self.intentSource ?: @"system",
        @"intentConfidence": @(self.intentConfidence),
        @"emotionLabel": self.emotionLabel ?: @"calm",
        @"emotionValence": @(self.emotionValence),
        @"emotionArousal": @(self.emotionArousal),
        @"behaviorState": self.behaviorState ?: @"idle",
        @"behaviorMode": self.behaviorMode ?: @"ambient",
        @"behaviorReason": self.behaviorReason ?: @"bootstrap",
        @"animationState": self.animationState ?: @"idle",
        @"context": self.context ?: @{},
        @"timestamp": @([self.timestamp timeIntervalSince1970])
    };
}

+ (instancetype)snapshotFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSString *intentName = [dictionary[@"intentName"] isKindOfClass:NSString.class] ? dictionary[@"intentName"] : @"ambient.exist";
    NSString *intentSource = [dictionary[@"intentSource"] isKindOfClass:NSString.class] ? dictionary[@"intentSource"] : @"system";
    double intentConfidence = [dictionary[@"intentConfidence"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"intentConfidence"] doubleValue] : 1.0;
    NSString *emotionLabel = [dictionary[@"emotionLabel"] isKindOfClass:NSString.class] ? dictionary[@"emotionLabel"] : @"calm";
    double emotionValence = [dictionary[@"emotionValence"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"emotionValence"] doubleValue] : 0.0;
    double emotionArousal = [dictionary[@"emotionArousal"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"emotionArousal"] doubleValue] : 0.0;
    NSString *behaviorState = [dictionary[@"behaviorState"] isKindOfClass:NSString.class] ? dictionary[@"behaviorState"] : @"idle";
    NSString *behaviorMode = [dictionary[@"behaviorMode"] isKindOfClass:NSString.class] ? dictionary[@"behaviorMode"] : @"ambient";
    NSString *behaviorReason = [dictionary[@"behaviorReason"] isKindOfClass:NSString.class] ? dictionary[@"behaviorReason"] : @"restored";
    NSString *animationState = [dictionary[@"animationState"] isKindOfClass:NSString.class] ? dictionary[@"animationState"] : behaviorState;
    NSDictionary<NSString *, id> *context = [dictionary[@"context"] isKindOfClass:NSDictionary.class] ? dictionary[@"context"] : @{};
    NSTimeInterval timestampValue = [dictionary[@"timestamp"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"timestamp"] doubleValue] : [[NSDate date] timeIntervalSince1970];
    NSDate *timestamp = [NSDate dateWithTimeIntervalSince1970:timestampValue];

    return [[self alloc] initWithIntentName:intentName
                               intentSource:intentSource
                           intentConfidence:intentConfidence
                               emotionLabel:emotionLabel
                             emotionValence:emotionValence
                             emotionArousal:emotionArousal
                              behaviorState:behaviorState
                               behaviorMode:behaviorMode
                             behaviorReason:behaviorReason
                             animationState:animationState
                                    context:context
                                  timestamp:timestamp];
}

- (NSString *)runtimeSummary {
    return [NSString stringWithFormat:@"Intent %@ | Emotion %@ | Behavior %@ | Animation %@",
            self.intentName ?: @"ambient.exist",
            self.emotionLabel ?: @"calm",
            self.behaviorState ?: @"idle",
            self.animationState ?: @"idle"];
}

@end
