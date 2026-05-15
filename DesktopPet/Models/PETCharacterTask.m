#import "PETCharacterTask.h"

@implementation PETCharacterTask

- (instancetype)initWithTaskIdentifier:(NSString *)taskIdentifier
                              taskName:(NSString *)taskName
                          taskCategory:(NSString *)taskCategory
                                status:(NSString *)status
                              priority:(NSInteger)priority
                              progress:(NSInteger)progress
                      requiredProgress:(NSInteger)requiredProgress
                               context:(NSDictionary<NSString *,id> *)context
                             createdAt:(NSDate *)createdAt
                             updatedAt:(NSDate *)updatedAt
                             expiresAt:(NSDate *)expiresAt {
    self = [super init];
    if (self) {
        _taskIdentifier = [taskIdentifier copy];
        _taskName = [taskName copy];
        _taskCategory = [taskCategory copy];
        _status = [status copy];
        _priority = priority;
        _progress = progress;
        _requiredProgress = requiredProgress;
        _context = [context copy] ?: @{};
        _createdAt = createdAt ?: [NSDate date];
        _updatedAt = updatedAt ?: [NSDate date];
        _expiresAt = expiresAt;
    }
    return self;
}

- (BOOL)isActiveAtDate:(NSDate *)date {
    if (![self.status isEqualToString:@"active"]) {
        return NO;
    }
    if (self.expiresAt == nil) {
        return YES;
    }
    return [self.expiresAt compare:date] == NSOrderedDescending;
}

- (NSDictionary<NSString *,id> *)serializedRepresentation {
    NSMutableDictionary<NSString *, id> *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"taskIdentifier"] = self.taskIdentifier ?: @"task";
    dictionary[@"taskName"] = self.taskName ?: @"task";
    dictionary[@"taskCategory"] = self.taskCategory ?: @"general";
    dictionary[@"status"] = self.status ?: @"active";
    dictionary[@"priority"] = @(self.priority);
    dictionary[@"progress"] = @(self.progress);
    dictionary[@"requiredProgress"] = @(self.requiredProgress);
    dictionary[@"context"] = self.context ?: @{};
    dictionary[@"createdAt"] = @([self.createdAt timeIntervalSince1970]);
    dictionary[@"updatedAt"] = @([self.updatedAt timeIntervalSince1970]);
    if (self.expiresAt != nil) {
        dictionary[@"expiresAt"] = @([self.expiresAt timeIntervalSince1970]);
    }
    return dictionary.copy;
}

+ (instancetype)taskFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *taskIdentifier = [dictionary[@"taskIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"taskIdentifier"] : nil;
    NSString *taskName = [dictionary[@"taskName"] isKindOfClass:NSString.class] ? dictionary[@"taskName"] : nil;
    NSString *taskCategory = [dictionary[@"taskCategory"] isKindOfClass:NSString.class] ? dictionary[@"taskCategory"] : nil;
    NSString *status = [dictionary[@"status"] isKindOfClass:NSString.class] ? dictionary[@"status"] : @"active";
    if (taskIdentifier.length == 0 || taskName.length == 0 || taskCategory.length == 0) {
        return nil;
    }
    NSInteger priority = [dictionary[@"priority"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"priority"] integerValue] : 0;
    NSInteger progress = [dictionary[@"progress"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"progress"] integerValue] : 0;
    NSInteger requiredProgress = [dictionary[@"requiredProgress"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"requiredProgress"] integerValue] : 1;
    NSDictionary<NSString *, id> *context = [dictionary[@"context"] isKindOfClass:NSDictionary.class] ? dictionary[@"context"] : @{};
    NSTimeInterval createdAtValue = [dictionary[@"createdAt"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"createdAt"] doubleValue] : [[NSDate date] timeIntervalSince1970];
    NSTimeInterval updatedAtValue = [dictionary[@"updatedAt"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"updatedAt"] doubleValue] : createdAtValue;
    NSDate *createdAt = [NSDate dateWithTimeIntervalSince1970:createdAtValue];
    NSDate *updatedAt = [NSDate dateWithTimeIntervalSince1970:updatedAtValue];
    NSDate *expiresAt = nil;
    if ([dictionary[@"expiresAt"] respondsToSelector:@selector(doubleValue)]) {
        expiresAt = [NSDate dateWithTimeIntervalSince1970:[dictionary[@"expiresAt"] doubleValue]];
    }
    return [[self alloc] initWithTaskIdentifier:taskIdentifier
                                       taskName:taskName
                                   taskCategory:taskCategory
                                         status:status
                                       priority:priority
                                       progress:progress
                               requiredProgress:requiredProgress
                                        context:context
                                      createdAt:createdAt
                                      updatedAt:updatedAt
                                      expiresAt:expiresAt];
}

@end
