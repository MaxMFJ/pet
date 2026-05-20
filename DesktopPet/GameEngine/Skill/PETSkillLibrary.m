#import "PETSkillLibrary.h"

#import "PETSkillDefinition.h"

static NSString * const PETSkillLibraryErrorDomain = @"PETSkillLibrary";

static NSURL *PETSkillLibraryFindResourceURL(NSString *relativePath) {
    if (relativePath.length == 0) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *searchRoots = [NSMutableArray array];

    NSString *resourcePath = NSBundle.mainBundle.resourcePath;
    if (resourcePath.length > 0) {
        [searchRoots addObject:resourcePath];
        NSString *bundlePath = NSBundle.mainBundle.bundlePath;
        if (bundlePath.length > 0) {
            [searchRoots addObject:bundlePath];
            NSString *parent = bundlePath.stringByDeletingLastPathComponent;
            for (NSUInteger depth = 0; depth < 5 && parent.length > 1; depth++) {
                [searchRoots addObject:parent];
                parent = parent.stringByDeletingLastPathComponent;
            }
        }
    }

    NSString *cwd = NSFileManager.defaultManager.currentDirectoryPath;
    if (cwd.length > 0) {
        [searchRoots addObject:cwd];
        NSString *parent = cwd.stringByDeletingLastPathComponent;
        for (NSUInteger depth = 0; depth < 5 && parent.length > 1; depth++) {
            [searchRoots addObject:parent];
            parent = parent.stringByDeletingLastPathComponent;
        }
    }

    NSArray<NSString *> *candidateRelativePaths = @[
        relativePath,
        [@"Resources/" stringByAppendingString:relativePath],
        [@"DesktopPet/Resources/" stringByAppendingString:relativePath],
    ];

    for (NSString *root in searchRoots) {
        for (NSString *candidateRelativePath in candidateRelativePaths) {
            NSString *candidatePath = [root stringByAppendingPathComponent:candidateRelativePath];
            if ([fileManager fileExistsAtPath:candidatePath]) {
                return [NSURL fileURLWithPath:candidatePath];
            }
        }
    }
    return nil;
}

@interface PETSkillLibrary ()

@property (nonatomic, assign) NSInteger formatVersion;
@property (nonatomic, copy) NSArray<PETSkillDefinition *> *skills;
@property (nonatomic, copy) NSDictionary<NSString *, PETSkillReactionDefinition *> *reactionDefinitionsByIdentifier;
@property (nonatomic, copy) NSDictionary<NSString *, PETSkillDefinition *> *skillDefinitionsByIdentifier;

- (instancetype)initWithRootDictionary:(NSDictionary<NSString *, id> *)root;

@end

@interface PETSkillReactionDefinition ()

@property (nonatomic, copy) NSString *reactionIdentifier;
@property (nonatomic, copy) NSString *combatState;
@property (nonatomic, copy, nullable) NSString *animationState;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) CGFloat gravityScale;
@property (nonatomic, assign) BOOL lockHorizontal;
@property (nonatomic, assign) BOOL lockVertical;
@property (nonatomic, assign, getter=isKnockdown) BOOL knockdown;
@property (nonatomic, assign) CGVector launchVector;
@property (nonatomic, copy) NSDictionary<NSString *, id> *dictionaryRepresentation;

@end

@implementation PETSkillReactionDefinition

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *,id> *)dictionary {
    self = [super init];
    if (self) {
        NSString *reactionIdentifier = [dictionary[@"reactionId"] isKindOfClass:NSString.class] ? dictionary[@"reactionId"] : @"";
        NSString *combatState = [dictionary[@"combatState"] isKindOfClass:NSString.class] ? dictionary[@"combatState"] : @"combat.hitstun";
        NSString *animationState = [dictionary[@"animationState"] isKindOfClass:NSString.class] ? dictionary[@"animationState"] : nil;
        NSDictionary<NSString *, id> *launchVector = [dictionary[@"launchVector"] isKindOfClass:NSDictionary.class] ? dictionary[@"launchVector"] : nil;

        _reactionIdentifier = [reactionIdentifier copy];
        _combatState = [combatState copy];
        _animationState = [animationState copy];
        _duration = MAX(0.0, [dictionary[@"duration"] doubleValue]);
        NSNumber *gravityScale = [dictionary[@"gravityScale"] respondsToSelector:@selector(doubleValue)] ? dictionary[@"gravityScale"] : nil;
        _gravityScale = gravityScale != nil ? gravityScale.doubleValue : 1.0;
        _lockHorizontal = [dictionary[@"lockHorizontal"] boolValue];
        _lockVertical = [dictionary[@"lockVertical"] boolValue];
        _knockdown = [dictionary[@"knockdown"] boolValue];
        _launchVector = CGVectorMake([launchVector[@"dx"] doubleValue], [launchVector[@"dy"] doubleValue]);
        _dictionaryRepresentation = [dictionary copy] ?: @{};
    }
    return self;
}

@end

@implementation PETSkillLibrary

- (instancetype)initWithBundle:(NSBundle *)bundle error:(NSError * _Nullable __autoreleasing *)error {
    NSURL *jsonURL = [bundle URLForResource:@"skills" withExtension:@"json" subdirectory:@"Skills"];
    if (jsonURL == nil) {
        jsonURL = PETSkillLibraryFindResourceURL(@"Skills/skills.json");
    }
    if (jsonURL != nil) {
        self = [self initWithJSONURL:jsonURL error:error];
        if (self == nil) {
            return nil;
        }
    } else {
        self = [self initWithRootDictionary:@{}];
    }

    NSURL *soulArkSkillsURL = [bundle URLForResource:@"skills-soul-ark" withExtension:@"json" subdirectory:@"Skills"];
    if (soulArkSkillsURL == nil) {
        soulArkSkillsURL = PETSkillLibraryFindResourceURL(@"Skills/skills-soul-ark.json");
    }
    if (soulArkSkillsURL != nil) {
        [self mergeFromJSONURL:soulArkSkillsURL error:nil];
    }
    NSURL *munjoongSkillsURL = [bundle URLForResource:@"skills-munjoong" withExtension:@"json" subdirectory:@"Skills"];
    if (munjoongSkillsURL == nil) {
        munjoongSkillsURL = PETSkillLibraryFindResourceURL(@"Skills/skills-munjoong.json");
    }
    if (munjoongSkillsURL != nil) {
        [self mergeFromJSONURL:munjoongSkillsURL error:nil];
    }

    if (self.skills.count == 0 && self.reactionDefinitionsByIdentifier.count == 0 && error != NULL) {
        *error = [NSError errorWithDomain:PETSkillLibraryErrorDomain
                                     code:9101
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to locate any ACT skill JSON resources."}];
    }
    return self;
}

- (instancetype)initWithJSONURL:(NSURL *)jsonURL error:(NSError * _Nullable __autoreleasing *)error {
    NSData *data = [NSData dataWithContentsOfURL:jsonURL options:0 error:error];
    if (data == nil) {
        return nil;
    }

    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![rootObject isKindOfClass:NSDictionary.class]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSkillLibraryErrorDomain
                                         code:9102
                                     userInfo:@{NSLocalizedDescriptionKey: @"skills.json root object must be a dictionary."}];
        }
        return nil;
    }

    NSDictionary<NSString *, id> *root = rootObject;
    return [self initWithRootDictionary:root];
}

- (instancetype)initWithRootDictionary:(NSDictionary<NSString *,id> *)root {
    self = [super init];
    if (self) {
        _formatVersion = [root[@"formatVersion"] integerValue];

        NSArray<NSDictionary<NSString *, id> *> *rawSkills = [root[@"skills"] isKindOfClass:NSArray.class] ? root[@"skills"] : @[];
        NSMutableArray<PETSkillDefinition *> *skills = [NSMutableArray arrayWithCapacity:rawSkills.count];
        NSMutableDictionary<NSString *, PETSkillDefinition *> *skillsByIdentifier = [NSMutableDictionary dictionaryWithCapacity:rawSkills.count];
        for (NSDictionary<NSString *, id> *rawSkill in rawSkills) {
            if (![rawSkill isKindOfClass:NSDictionary.class]) {
                continue;
            }
            PETSkillDefinition *definition = [[PETSkillDefinition alloc] initWithDictionaryRepresentation:rawSkill];
            [skills addObject:definition];
            if (definition.skillIdentifier.length > 0) {
                skillsByIdentifier[definition.skillIdentifier] = definition;
            }
        }

        NSArray<NSDictionary<NSString *, id> *> *rawReactions = [root[@"reactions"] isKindOfClass:NSArray.class] ? root[@"reactions"] : @[];
        NSMutableDictionary<NSString *, PETSkillReactionDefinition *> *reactionsByIdentifier = [NSMutableDictionary dictionaryWithCapacity:rawReactions.count];
        for (NSDictionary<NSString *, id> *reaction in rawReactions) {
            if (![reaction isKindOfClass:NSDictionary.class]) {
                continue;
            }
            PETSkillReactionDefinition *definition = [[PETSkillReactionDefinition alloc] initWithDictionaryRepresentation:reaction];
            if (definition.reactionIdentifier.length == 0) {
                continue;
            }
            reactionsByIdentifier[definition.reactionIdentifier] = definition;
        }

        _skills = [skills copy];
        _skillDefinitionsByIdentifier = [skillsByIdentifier copy];
        _reactionDefinitionsByIdentifier = [reactionsByIdentifier copy];
    }
    return self;
}

- (PETSkillDefinition *)skillDefinitionForIdentifier:(NSString *)skillIdentifier {
    if (skillIdentifier.length == 0) {
        return nil;
    }
    return self.skillDefinitionsByIdentifier[skillIdentifier];
}

- (PETSkillReactionDefinition *)reactionDefinitionForIdentifier:(NSString *)reactionIdentifier {
    if (reactionIdentifier.length == 0) {
        return nil;
    }
    return self.reactionDefinitionsByIdentifier[reactionIdentifier];
}

- (BOOL)mergeFromJSONURL:(NSURL *)jsonURL error:(NSError *__autoreleasing *)error {
    NSData *data = [NSData dataWithContentsOfURL:jsonURL options:0 error:error];
    if (data == nil) {
        return NO;
    }

    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![rootObject isKindOfClass:NSDictionary.class]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSkillLibraryErrorDomain
                                         code:9103
                                     userInfo:@{NSLocalizedDescriptionKey: @"Merged skill JSON root object must be a dictionary."}];
        }
        return NO;
    }

    NSDictionary<NSString *, id> *root = rootObject;
    NSMutableArray<PETSkillDefinition *> *skills = [self.skills mutableCopy] ?: [NSMutableArray array];
    NSMutableDictionary<NSString *, PETSkillDefinition *> *skillsByIdentifier = [self.skillDefinitionsByIdentifier mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, PETSkillReactionDefinition *> *reactionsByIdentifier = [self.reactionDefinitionsByIdentifier mutableCopy] ?: [NSMutableDictionary dictionary];

    NSArray<NSDictionary<NSString *, id> *> *rawSkills = [root[@"skills"] isKindOfClass:NSArray.class] ? root[@"skills"] : @[];
    for (NSDictionary<NSString *, id> *rawSkill in rawSkills) {
        if (![rawSkill isKindOfClass:NSDictionary.class]) {
            continue;
        }
        PETSkillDefinition *definition = [[PETSkillDefinition alloc] initWithDictionaryRepresentation:rawSkill];
        if (definition.skillIdentifier.length == 0) {
            continue;
        }
        NSUInteger existingIndex = [skills indexOfObjectPassingTest:^BOOL(PETSkillDefinition *existingDefinition, NSUInteger idx, BOOL *stop) {
            (void)idx;
            (void)stop;
            return [existingDefinition.skillIdentifier isEqualToString:definition.skillIdentifier];
        }];
        if (existingIndex != NSNotFound) {
            [skills replaceObjectAtIndex:existingIndex withObject:definition];
        } else {
            [skills addObject:definition];
        }
        skillsByIdentifier[definition.skillIdentifier] = definition;
    }

    NSArray<NSDictionary<NSString *, id> *> *rawReactions = [root[@"reactions"] isKindOfClass:NSArray.class] ? root[@"reactions"] : @[];
    for (NSDictionary<NSString *, id> *reaction in rawReactions) {
        if (![reaction isKindOfClass:NSDictionary.class]) {
            continue;
        }
        PETSkillReactionDefinition *definition = [[PETSkillReactionDefinition alloc] initWithDictionaryRepresentation:reaction];
        if (definition.reactionIdentifier.length == 0) {
            continue;
        }
        reactionsByIdentifier[definition.reactionIdentifier] = definition;
    }

    self.skills = skills.copy;
    self.skillDefinitionsByIdentifier = skillsByIdentifier.copy;
    self.reactionDefinitionsByIdentifier = reactionsByIdentifier.copy;
    return YES;
}

@end
