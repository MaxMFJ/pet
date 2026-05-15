#import "PETIntentEngine.h"

#import "../Models/PETCharacterIntent.h"
#import "PETCharacterSemanticConfig.h"

@implementation PETIntentEngine

- (PETCharacterIntent *)intentForActionKey:(NSString *)actionKey
                     fallbackBehaviorState:(NSString *)fallbackBehaviorState
                    resolvedAnimationState:(NSString *)resolvedAnimationState
                                   context:(NSDictionary<NSString *,id> *)context {
    NSDictionary<NSString *, id> *rule = [[PETCharacterSemanticConfig sharedConfig] intentRuleForActionKey:actionKey ?: @""];
    NSString *name = [rule[@"intentName"] isKindOfClass:NSString.class] ? rule[@"intentName"] : @"runtime.react";
    NSString *source = [rule[@"source"] isKindOfClass:NSString.class] ? rule[@"source"] : @"runtime.window";
    double confidence = [rule[@"confidence"] respondsToSelector:@selector(doubleValue)] ? [rule[@"confidence"] doubleValue] : 0.92;

    return [[PETCharacterIntent alloc] initWithName:name
                                             source:source
                                         confidence:confidence
                                          actionKey:actionKey ?: @"runtime.react"
                              fallbackBehaviorState:fallbackBehaviorState ?: @""
                             resolvedAnimationState:resolvedAnimationState ?: @""
                                            context:context];
}

- (PETCharacterIntent *)ambientIntentWithAnimationState:(NSString *)animationState
                                                context:(NSDictionary<NSString *,id> *)context {
    return [self intentForActionKey:@"ambient.idle"
              fallbackBehaviorState:@"idle"
             resolvedAnimationState:animationState
                            context:context];
}

- (PETCharacterIntent *)manualPreviewIntentWithAnimationState:(NSString *)animationState
                                                      context:(NSDictionary<NSString *,id> *)context {
    return [self intentForActionKey:@"manual.preview"
              fallbackBehaviorState:animationState
             resolvedAnimationState:animationState
                            context:context];
}

@end
