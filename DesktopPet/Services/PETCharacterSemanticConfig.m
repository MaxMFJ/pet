#import "PETCharacterSemanticConfig.h"

@interface PETCharacterSemanticConfig ()

@property (nonatomic, copy) NSDictionary<NSString *, id> *semanticMappings;

@end

@implementation PETCharacterSemanticConfig

+ (instancetype)sharedConfig {
    static PETCharacterSemanticConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [[PETCharacterSemanticConfig alloc] initPrivate];
    });
    return config;
}

- (instancetype)init {
    return [PETCharacterSemanticConfig sharedConfig];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _semanticMappings = [self loadMappings];
    }
    return self;
}

- (NSDictionary<NSString *,id> *)intentRuleForActionKey:(NSString *)actionKey {
    NSDictionary<NSString *, id> *intentRules = [self.semanticMappings[@"intentRules"] isKindOfClass:NSDictionary.class] ? self.semanticMappings[@"intentRules"] : @{};
    return [self resolveRuleInSection:intentRules actionKey:actionKey intentName:nil];
}

- (NSDictionary<NSString *,id> *)behaviorRuleForIntentName:(NSString *)intentName
                                                 actionKey:(NSString *)actionKey {
    NSDictionary<NSString *, id> *behaviorRules = [self.semanticMappings[@"behaviorRules"] isKindOfClass:NSDictionary.class] ? self.semanticMappings[@"behaviorRules"] : @{};
    return [self resolveRuleInSection:behaviorRules actionKey:actionKey intentName:intentName];
}

- (NSDictionary<NSString *,id> *)emotionRuleForIntentName:(NSString *)intentName
                                                 actionKey:(NSString *)actionKey {
    NSDictionary<NSString *, id> *emotionRules = [self.semanticMappings[@"emotionRules"] isKindOfClass:NSDictionary.class] ? self.semanticMappings[@"emotionRules"] : @{};
    return [self resolveRuleInSection:emotionRules actionKey:actionKey intentName:intentName];
}

- (NSDictionary<NSString *,id> *)goalRuleForIntentName:(NSString *)intentName
                                             actionKey:(NSString *)actionKey {
    NSDictionary<NSString *, id> *goalRules = [self.semanticMappings[@"goalRules"] isKindOfClass:NSDictionary.class] ? self.semanticMappings[@"goalRules"] : @{};
    return [self resolveRuleInSection:goalRules actionKey:actionKey intentName:intentName];
}

- (NSDictionary<NSString *,id> *)taskRuleForIntentName:(NSString *)intentName
                                             actionKey:(NSString *)actionKey {
    NSDictionary<NSString *, id> *taskRules = [self.semanticMappings[@"taskRules"] isKindOfClass:NSDictionary.class] ? self.semanticMappings[@"taskRules"] : @{};
    return [self resolveRuleInSection:taskRules actionKey:actionKey intentName:intentName];
}

- (NSDictionary<NSString *, id> *)loadMappings {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"PETCharacterSemanticMappings" withExtension:@"plist"];
    if (url == nil) {
        return @{};
    }

    NSDictionary<NSString *, id> *mappings = [NSDictionary dictionaryWithContentsOfURL:url];
    return [mappings isKindOfClass:NSDictionary.class] ? mappings : @{};
}

- (NSDictionary<NSString *, id> *)resolveRuleInSection:(NSDictionary<NSString *, id> *)section
                                             actionKey:(NSString *)actionKey
                                            intentName:(nullable NSString *)intentName {
    NSDictionary<NSString *, id> *exactAction = [section[@"exactAction"] isKindOfClass:NSDictionary.class] ? section[@"exactAction"] : @{};
    NSDictionary<NSString *, id> *exactIntent = [section[@"exactIntent"] isKindOfClass:NSDictionary.class] ? section[@"exactIntent"] : @{};
    NSArray<NSDictionary<NSString *, id> *> *prefixAction = [section[@"prefixAction"] isKindOfClass:NSArray.class] ? section[@"prefixAction"] : @[];
    NSArray<NSDictionary<NSString *, id> *> *prefixIntent = [section[@"prefixIntent"] isKindOfClass:NSArray.class] ? section[@"prefixIntent"] : @[];
    NSDictionary<NSString *, id> *defaultRule = [section[@"default"] isKindOfClass:NSDictionary.class] ? section[@"default"] : @{};

    NSDictionary<NSString *, id> *rule = nil;
    if (actionKey.length > 0) {
        rule = [exactAction[actionKey] isKindOfClass:NSDictionary.class] ? exactAction[actionKey] : nil;
    }
    if (rule == nil && intentName.length > 0) {
        rule = [exactIntent[intentName] isKindOfClass:NSDictionary.class] ? exactIntent[intentName] : nil;
    }
    if (rule == nil && actionKey.length > 0) {
        rule = [self firstPrefixRuleInRules:prefixAction value:actionKey];
    }
    if (rule == nil && intentName.length > 0) {
        rule = [self firstPrefixRuleInRules:prefixIntent value:intentName];
    }
    return rule ?: defaultRule;
}

- (nullable NSDictionary<NSString *, id> *)firstPrefixRuleInRules:(NSArray<NSDictionary<NSString *, id> *> *)rules
                                                            value:(NSString *)value {
    for (NSDictionary<NSString *, id> *rule in rules) {
        NSString *match = [rule[@"match"] isKindOfClass:NSString.class] ? rule[@"match"] : nil;
        if (match.length > 0 && [value hasPrefix:match]) {
            return rule;
        }
    }
    return nil;
}

@end
