#import "PETCombatCharacterCatalog.h"

#import "../Core/PETGameCommand.h"
#import "../Skill/PETSkillLibrary.h"
#import "PETCombatKeyboardBinding.h"

NSString * const PETSoulArkCharacterSourceStemPrefix = @"char_";
NSString * const PETSoulArkCharacterDefaultProfileStem = @"__soul_ark_char_default__";

static NSURL *PETCombatCatalogFindBundledResourceURL(NSString *relativePath) {
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
        relativePath.lastPathComponent ?: relativePath,
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

static NSArray<NSURL *> *PETCombatCatalogFilesystemProfileURLs(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSArray<NSString *> *roots = @[
        NSBundle.mainBundle.resourcePath ?: @"",
        NSBundle.mainBundle.bundlePath ?: @"",
        NSFileManager.defaultManager.currentDirectoryPath ?: @"",
    ];
    NSArray<NSString *> *candidateDirectories = @[
        @"Combat/pets",
        @"Resources/Combat/pets",
        @"DesktopPet/Resources/Combat/pets",
    ];
    for (NSString *root in roots) {
        if (root.length == 0) {
            continue;
        }
        for (NSString *candidateDirectory in candidateDirectories) {
            NSString *directoryPath = [root stringByAppendingPathComponent:candidateDirectory];
            BOOL isDirectory = NO;
            if (![fileManager fileExistsAtPath:directoryPath isDirectory:&isDirectory] || !isDirectory) {
                continue;
            }
            NSArray<NSString *> *contents = [fileManager contentsOfDirectoryAtPath:directoryPath error:nil];
            for (NSString *name in contents) {
                if ([name.pathExtension.lowercaseString isEqualToString:@"json"]) {
                    [urls addObject:[NSURL fileURLWithPath:[directoryPath stringByAppendingPathComponent:name]]];
                }
            }
        }
    }
    return urls.copy;
}

static BOOL PETSourceStemMatchesSoulArkPrefix(NSString *sourceStem) {
    NSString *normalizedStem = sourceStem.lowercaseString ?: @"";
    return normalizedStem.length > PETSoulArkCharacterSourceStemPrefix.length
        && [normalizedStem hasPrefix:PETSoulArkCharacterSourceStemPrefix];
}

@interface PETCombatCharacterProfile ()

@property (nonatomic, copy) NSString *characterIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *sourceStem;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *interactionAliases;
@property (nonatomic, copy) NSDictionary<NSString *, PETCombatKeyboardBinding *> *bindingsByKey;

@end

@implementation PETCombatCharacterProfile

- (nullable PETCombatKeyboardBinding *)bindingForKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    return self.bindingsByKey[key.lowercaseString];
}

@end

@interface PETCombatCharacterCatalog ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, PETCombatCharacterProfile *> *mutableProfilesBySourceStem;
@property (nonatomic, strong, nullable) PETCombatCharacterProfile *soulArkCharacterDefaultProfile;

@end

@implementation PETCombatCharacterCatalog

- (instancetype)initWithBundle:(NSBundle *)bundle skillLibrary:(PETSkillLibrary *)skillLibrary {
    self = [super init];
    if (self) {
        _mutableProfilesBySourceStem = [NSMutableDictionary dictionary];
        _soulArkCharacterDefaultProfile = nil;
        [self loadProfilesFromBundle:bundle skillLibrary:skillLibrary];
    }
    return self;
}

- (void)registerProfile:(PETCombatCharacterProfile *)profile forSourceStem:(NSString *)sourceStem {
    if (profile == nil || sourceStem.length == 0) {
        return;
    }
    self.mutableProfilesBySourceStem[sourceStem] = profile;
    self.mutableProfilesBySourceStem[sourceStem.lowercaseString] = profile;
}

- (NSDictionary<NSString *, PETCombatCharacterProfile *> *)profilesBySourceStem {
    return self.mutableProfilesBySourceStem.copy;
}

- (nullable PETCombatCharacterProfile *)specificProfileForSourceStem:(NSString *)sourceStem {
    if (sourceStem.length == 0) {
        return nil;
    }

    PETCombatCharacterProfile *exactProfile = self.mutableProfilesBySourceStem[sourceStem];
    if (exactProfile != nil && exactProfile != self.soulArkCharacterDefaultProfile) {
        return exactProfile;
    }

    exactProfile = self.mutableProfilesBySourceStem[sourceStem.lowercaseString];
    if (exactProfile != nil && exactProfile != self.soulArkCharacterDefaultProfile) {
        return exactProfile;
    }

    NSString *normalizedSourceStem = sourceStem.lowercaseString ?: @"";
    for (NSString *knownStem in self.mutableProfilesBySourceStem) {
        if ([knownStem isEqualToString:PETSoulArkCharacterDefaultProfileStem]) {
            continue;
        }
        PETCombatCharacterProfile *profile = self.mutableProfilesBySourceStem[knownStem];
        if (profile == nil || profile == self.soulArkCharacterDefaultProfile) {
            continue;
        }
        NSString *normalizedKnownStem = knownStem.lowercaseString ?: @"";
        if ([normalizedSourceStem containsString:normalizedKnownStem] || [normalizedKnownStem containsString:normalizedSourceStem]) {
            return profile;
        }
    }

    return nil;
}

- (void)loadProfilesFromBundle:(NSBundle *)bundle skillLibrary:(PETSkillLibrary *)skillLibrary {
    NSMutableArray<NSURL *> *profileURLs = [NSMutableArray array];
    NSURL *petsDirectoryURL = [bundle URLForResource:@"pets" withExtension:nil subdirectory:@"Combat"];
    if (petsDirectoryURL != nil) {
        NSArray<NSURL *> *directoryURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:petsDirectoryURL
                                                                        includingPropertiesForKeys:nil
                                                                                           options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                             error:nil];
        if (directoryURLs.count > 0) {
            [profileURLs addObjectsFromArray:directoryURLs];
        }
    }

    for (NSString *subdirectory in @[@"Combat/pets", @"pets", @"Combat"]) {
        NSArray<NSURL *> *resourceURLs = [bundle URLsForResourcesWithExtension:@"json" subdirectory:subdirectory];
        for (NSURL *resourceURL in resourceURLs) {
            if (![profileURLs containsObject:resourceURL]) {
                [profileURLs addObject:resourceURL];
            }
        }
    }

    for (NSURL *resourceURL in PETCombatCatalogFilesystemProfileURLs()) {
        if (![profileURLs containsObject:resourceURL]) {
            [profileURLs addObject:resourceURL];
        }
    }

    for (NSURL *profileURL in profileURLs) {
        if (![profileURL.pathExtension isEqualToString:@"json"]) {
            continue;
        }
        if ([profileURL.lastPathComponent isEqualToString:@"combat-keybindings.json"]) {
            continue;
        }
        NSData *data = [NSData dataWithContentsOfURL:profileURL];
        id rootObject = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        PETCombatCharacterProfile *profile = [self profileFromJSONObject:rootObject jsonURL:profileURL skillLibrary:skillLibrary];
        if (profile == nil) {
            continue;
        }
        NSString *appliesToPrefix = [self appliesToSourceStemPrefixFromRootObject:rootObject];
        if ([profile.sourceStem isEqualToString:PETSoulArkCharacterDefaultProfileStem]
            || [appliesToPrefix isEqualToString:PETSoulArkCharacterSourceStemPrefix]) {
            self.soulArkCharacterDefaultProfile = profile;
            continue;
        }
        if (profile.sourceStem.length > 0) {
            self.mutableProfilesBySourceStem[profile.sourceStem] = profile;
            self.mutableProfilesBySourceStem[profile.sourceStem.lowercaseString] = profile;
        }
    }
}

- (NSString *)appliesToSourceStemPrefixFromRootObject:(id)rootObject {
    if (![rootObject isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *prefix = [rootObject[@"appliesToSourceStemPrefix"] isKindOfClass:NSString.class] ? rootObject[@"appliesToSourceStemPrefix"] : nil;
    return prefix.length > 0 ? prefix : nil;
}

- (nullable PETCombatCharacterProfile *)profileFromJSONURL:(NSURL *)jsonURL skillLibrary:(PETSkillLibrary *)skillLibrary {
    NSData *data = [NSData dataWithContentsOfURL:jsonURL];
    if (data.length == 0) {
        return nil;
    }
    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [self profileFromJSONObject:rootObject jsonURL:jsonURL skillLibrary:skillLibrary];
}

- (nullable PETCombatCharacterProfile *)profileFromJSONObject:(id)rootObject
                                                       jsonURL:(NSURL *)jsonURL
                                                  skillLibrary:(PETSkillLibrary *)skillLibrary {
    if (![rootObject isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSDictionary<NSString *, id> *root = rootObject;
    NSString *sourceStem = [root[@"sourceStem"] isKindOfClass:NSString.class] ? root[@"sourceStem"] : jsonURL.URLByDeletingPathExtension.lastPathComponent;
    NSString *characterIdentifier = [root[@"characterId"] isKindOfClass:NSString.class] ? root[@"characterId"] : sourceStem;
    NSString *displayName = [root[@"displayName"] isKindOfClass:NSString.class] ? root[@"displayName"] : characterIdentifier;

    NSDictionary<NSString *, NSString *> *interactionAliases = @{};
    NSDictionary<NSString *, id> *rawAliases = [root[@"interactionAliases"] isKindOfClass:NSDictionary.class] ? root[@"interactionAliases"] : nil;
    if (rawAliases.count > 0) {
        NSMutableDictionary<NSString *, NSString *> *aliases = [NSMutableDictionary dictionaryWithCapacity:rawAliases.count];
        [rawAliases enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            (void)stop;
            if ([obj isKindOfClass:NSString.class]) {
                aliases[key] = obj;
            }
        }];
        interactionAliases = aliases.copy;
    }

    NSArray<NSDictionary<NSString *, id> *> *rawBindings = [root[@"bindings"] isKindOfClass:NSArray.class] ? root[@"bindings"] : @[];
    NSMutableDictionary<NSString *, PETCombatKeyboardBinding *> *bindingsByKey = [NSMutableDictionary dictionaryWithCapacity:rawBindings.count];
    for (NSDictionary<NSString *, id> *rawBinding in rawBindings) {
        if (![rawBinding isKindOfClass:NSDictionary.class]) {
            continue;
        }
        PETCombatKeyboardBinding *binding = [[PETCombatKeyboardBinding alloc] initWithDictionaryRepresentation:rawBinding];
        if (binding.key.length == 0 || binding.commandType.length == 0) {
            continue;
        }
        if (binding.skillIdentifier.length > 0 && skillLibrary != nil && [skillLibrary skillDefinitionForIdentifier:binding.skillIdentifier] == nil) {
            NSLog(@"[DesktopPet] Combat binding kept despite unknown skillId=%@ key=%@ sourceStem=%@",
                  binding.skillIdentifier,
                  binding.key,
                  sourceStem ?: @"");
        }
        bindingsByKey[binding.key] = binding;
    }

    if (bindingsByKey.count == 0) {
        return nil;
    }

    PETCombatCharacterProfile *profile = [[PETCombatCharacterProfile alloc] init];
    profile.characterIdentifier = [characterIdentifier copy];
    profile.displayName = [displayName copy];
    profile.sourceStem = [sourceStem copy];
    profile.interactionAliases = interactionAliases;
    profile.bindingsByKey = bindingsByKey.copy;
    return profile;
}

- (nullable PETCombatCharacterProfile *)profileForSourceStem:(NSString *)sourceStem {
    if (sourceStem.length == 0) {
        return nil;
    }

    PETCombatCharacterProfile *specificProfile = [self specificProfileForSourceStem:sourceStem];
    if (specificProfile != nil) {
        return specificProfile;
    }

    if (PETSourceStemMatchesSoulArkPrefix(sourceStem)) {
        return self.soulArkCharacterDefaultProfile;
    }

    return nil;
}

- (nullable PETCombatCharacterProfile *)profileForSourceURL:(NSURL *)sourceURL {
    if (sourceURL == nil) {
        return nil;
    }
    NSString *stem = sourceURL.lastPathComponent.stringByDeletingPathExtension ?: @"";
    PETCombatCharacterProfile *profile = [self profileForSourceStem:stem];
    if (profile != nil) {
        return profile;
    }

    NSString *normalizedSourcePath = sourceURL.path.lowercaseString ?: @"";
    for (NSString *knownStem in self.mutableProfilesBySourceStem) {
        if ([knownStem isEqualToString:PETSoulArkCharacterDefaultProfileStem]) {
            continue;
        }
        if ([normalizedSourcePath containsString:knownStem.lowercaseString]) {
            return self.mutableProfilesBySourceStem[knownStem];
        }
    }

    if (PETSourceStemMatchesSoulArkPrefix(stem)) {
        return self.soulArkCharacterDefaultProfile;
    }
    return nil;
}

- (nullable PETCombatCharacterProfile *)loadProfileForSourceURL:(NSURL *)sourceURL skillLibrary:(PETSkillLibrary *)skillLibrary {
    PETCombatCharacterProfile *cachedProfile = [self profileForSourceURL:sourceURL];
    NSString *stem = sourceURL.lastPathComponent.stringByDeletingPathExtension ?: @"";
    BOOL shouldAttemptSpecificOverrideLoad = PETSourceStemMatchesSoulArkPrefix(stem)
        && (cachedProfile == nil || cachedProfile == self.soulArkCharacterDefaultProfile);
    if (cachedProfile != nil && !shouldAttemptSpecificOverrideLoad) {
        return cachedProfile;
    }

    NSURL *directoryURL = sourceURL.URLByDeletingLastPathComponent;
    NSArray<NSString *> *candidateNames = @[
        @"combat-bindings.json",
        [NSString stringWithFormat:@"%@.combat.json", stem],
        [NSString stringWithFormat:@"%@.json", stem],
    ];
    for (NSString *candidateName in candidateNames) {
        NSURL *candidateURL = [directoryURL URLByAppendingPathComponent:candidateName];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidateURL.path]) {
            continue;
        }
        PETCombatCharacterProfile *profile = [self profileFromJSONURL:candidateURL skillLibrary:skillLibrary];
        if (profile != nil) {
            [self registerProfile:profile forSourceStem:profile.sourceStem.length > 0 ? profile.sourceStem : stem];
            return profile;
        }
    }

    NSString *bundleCompanionRelativePath = [NSString stringWithFormat:@"Combat/pets/%@.combat-bindings.json", stem];
    NSURL *bundleCompanionURL = PETCombatCatalogFindBundledResourceURL(bundleCompanionRelativePath);
    if (bundleCompanionURL != nil) {
        PETCombatCharacterProfile *profile = [self profileFromJSONURL:bundleCompanionURL skillLibrary:skillLibrary];
        if (profile != nil) {
            [self registerProfile:profile forSourceStem:profile.sourceStem.length > 0 ? profile.sourceStem : stem];
            return profile;
        }
    }

    PETCombatCharacterProfile *bundleSpecificProfile = [self specificProfileForSourceStem:stem];
    if (bundleSpecificProfile != nil) {
        return bundleSpecificProfile;
    }

    if (cachedProfile != nil) {
        return cachedProfile;
    }

    if (PETSourceStemMatchesSoulArkPrefix(stem)) {
        NSURL *bundleDefaultURL = PETCombatCatalogFindBundledResourceURL(@"Combat/pets/char_soul_ark_default.json");
        PETCombatCharacterProfile *defaultProfile = self.soulArkCharacterDefaultProfile;
        if (defaultProfile == nil && bundleDefaultURL != nil) {
            defaultProfile = [self profileFromJSONURL:bundleDefaultURL skillLibrary:skillLibrary];
            if (defaultProfile != nil) {
                self.soulArkCharacterDefaultProfile = defaultProfile;
            }
        }
        if (defaultProfile != nil) {
            return defaultProfile;
        }
    }
    return nil;
}

@end
