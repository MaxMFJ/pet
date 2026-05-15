#import "PETCharacterGoal.h"

@implementation PETCharacterGoal

- (instancetype)initWithGoalIdentifier:(NSString *)goalIdentifier
                              goalName:(NSString *)goalName
                          goalCategory:(NSString *)goalCategory
                   targetBehaviorState:(NSString *)targetBehaviorState
                              priority:(NSInteger)priority
                             expiresAt:(NSDate *)expiresAt
                               context:(NSDictionary<NSString *,id> *)context {
    self = [super init];
    if (self) {
        _goalIdentifier = [goalIdentifier copy];
        _goalName = [goalName copy];
        _goalCategory = [goalCategory copy];
        _targetBehaviorState = [targetBehaviorState copy];
        _priority = priority;
        _expiresAt = expiresAt;
        _context = [context copy] ?: @{};
    }
    return self;
}

- (BOOL)isActiveAtDate:(NSDate *)date {
    if (self.expiresAt == nil) {
        return YES;
    }
    return [self.expiresAt compare:date] == NSOrderedDescending;
}

- (NSDictionary<NSString *,id> *)serializedRepresentation {
    NSMutableDictionary<NSString *, id> *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"goalIdentifier"] = self.goalIdentifier ?: @"goal";
    dictionary[@"goalName"] = self.goalName ?: @"goal";
    dictionary[@"goalCategory"] = self.goalCategory ?: @"general";
    dictionary[@"targetBehaviorState"] = self.targetBehaviorState ?: @"idle";
    dictionary[@"priority"] = @(self.priority);
    dictionary[@"context"] = self.context ?: @{};
    if (self.expiresAt != nil) {
        dictionary[@"expiresAt"] = @([self.expiresAt timeIntervalSince1970]);
    }
    return dictionary.copy;
}

+ (instancetype)goalFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *goalIdentifier = [dictionary[@"goalIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"goalIdentifier"] : nil;
    NSString *goalName = [dictionary[@"goalName"] isKindOfClass:NSString.class] ? dictionary[@"goalName"] : nil;
    NSString *goalCategory = [dictionary[@"goalCategory"] isKindOfClass:NSString.class] ? dictionary[@"goalCategory"] : nil;
    NSString *targetBehaviorState = [dictionary[@"targetBehaviorState"] isKindOfClass:NSString.class] ? dictionary[@"targetBehaviorState"] : nil;
    if (goalIdentifier.length == 0 || goalName.length == 0 || goalCategory.length == 0 || targetBehaviorState.length == 0) {
        return nil;
    }
    NSInteger priority = [dictionary[@"priority"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"priority"] integerValue] : 0;
    NSDate *expiresAt = nil;
    if ([dictionary[@"expiresAt"] respondsToSelector:@selector(doubleValue)]) {
        expiresAt = [NSDate dateWithTimeIntervalSince1970:[dictionary[@"expiresAt"] doubleValue]];
    }
    NSDictionary<NSString *, id> *context = [dictionary[@"context"] isKindOfClass:NSDictionary.class] ? dictionary[@"context"] : @{};
    return [[self alloc] initWithGoalIdentifier:goalIdentifier
                                       goalName:goalName
                                   goalCategory:goalCategory
                            targetBehaviorState:targetBehaviorState
                                       priority:priority
                                      expiresAt:expiresAt
                                        context:context];
}

@end
