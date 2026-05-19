#import "PETPetManager.h"

#import "../Config/PETAppConfig.h"
#import "../GameEngine/Core/PETGameCommand.h"
#import "../GameEngine/Core/PETGameEngine.h"
#import "../GameEngine/Core/PETGameEvent.h"
#import "../GameEngine/Skill/PETSkillLibrary.h"
#import "../GameEngine/Input/PETCombatCharacterCatalog.h"
#import "../GameEngine/Input/PETCombatKeyboardBindings.h"
#import "../GameEngine/Input/PETKeyboardInputRouter.h"
#import "../GameEngine/Presentation/PETGamePresentationBridge.h"
#import "../Models/PETPetProfile.h"
#import "../Models/PETStructuredCognitionSuggestion.h"
#import "../Services/PETAIService.h"
#import "../Services/PETCharacterRuntimeController.h"
#import "../Services/PETOCRService.h"
#import "../Services/PETStructuredCognitionEngine.h"
#import "../UI/PETPetWindow.h"

NSNotificationName const PETPetManagerDidChangePetsNotification = @"PETPetManagerDidChangePetsNotification";
NSNotificationName const PETPetManagerDidUpdateRuntimeDebugNotification = @"PETPetManagerDidUpdateRuntimeDebugNotification";
static NSString * const PETProfileMetadataSoulArkEnabledKey = @"灵魂方舟";
static NSString * const PETProfileMetadataSoulArkFacingInvertedKey = @"灵魂方舟左右方向反转";
static CGFloat const PETPetManagerDefaultScale = 0.3;

static NSURL *PETPetManagerFindBundledResourceURL(NSString *relativePath) {
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

@interface PETPetManager ()

@property (nonatomic, strong) PETAppConfig *configuration;
@property (nonatomic, strong) NSMutableArray<PETPetProfile *> *mutableProfiles;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PETPetWindow *> *petWindows;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *petScales;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *petFacingDirections;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *petClickThrough;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PETCharacterRuntimeController *> *runtimeControllers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *characterSnapshots;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *gameStates;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *combatDebugSnapshots;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *lastCollisionSnapshots;
@property (nonatomic, strong) NSMutableSet<NSString *> *hiddenProfileIdentifiers;
@property (nonatomic, strong) PETGameEngine *gameEngine;
@property (nonatomic, strong) PETKeyboardInputRouter *keyboardInputRouter;
@property (nonatomic, strong, nullable) PETCombatKeyboardBindings *combatKeyboardBindings;
@property (nonatomic, strong) PETCombatCharacterCatalog *combatCharacterCatalog;
@property (nonatomic, strong) PETGamePresentationBridge *gamePresentationBridge;
@property (nonatomic, strong) PETStructuredCognitionEngine *cognitionEngine;
@property (nonatomic, strong) PETOCRService *ocrService;
@property (nonatomic, strong) NSTimer *ocrPollingTimer;
@property (nonatomic, strong) NSTimer *cognitionPollingTimer;
@property (nonatomic, copy) NSString *lastOCRSignature;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastCognitionTimestamps;
@property (nonatomic, strong) NSMutableSet<NSString *> *mergedCombatSkillResourcePaths;
@property (nonatomic, copy, nullable, readwrite) NSString *selectedPetIdentifier;

@end

@implementation PETPetManager

- (nullable PETPetProfile *)profileMatchingSourceURL:(NSURL *)sourceURL {
    NSString *sourcePath = sourceURL.path;
    if (sourcePath.length == 0) {
        return nil;
    }

    for (PETPetProfile *profile in self.mutableProfiles) {
        if ([profile.sourceURL.path isEqualToString:sourcePath]) {
            return profile;
        }
    }
    return nil;
}

- (nullable PETPetProfile *)firstHiddenProfile {
    for (PETPetProfile *profile in self.mutableProfiles) {
        if (![self isPetVisible:profile]) {
            return profile;
        }
    }
    return nil;
}

- (nullable PETPetProfile *)firstVisibleProfileExcludingProfile:(nullable PETPetProfile *)excludedProfile {
    for (PETPetProfile *profile in self.mutableProfiles) {
        if (excludedProfile != nil && [profile.identifier isEqualToString:excludedProfile.identifier]) {
            continue;
        }
        if ([self isPetVisible:profile]) {
            return profile;
        }
    }
    return nil;
}

- (NSUInteger)visiblePetCount {
    NSUInteger count = 0;
    for (PETPetProfile *profile in self.mutableProfiles) {
        if ([self isPetVisible:profile]) {
            count += 1;
        }
    }
    return count;
}

- (CGPoint)defaultOriginForProfileCount:(NSUInteger)profileCount {
    NSScreen *screen = NSScreen.mainScreen;
    NSRect screenFrame = screen.frame;
    CGFloat horizontalOffset = 24.0 + (CGFloat)(profileCount * 40);
    CGFloat verticalOffset = 48.0 + (CGFloat)(profileCount * 24);
    return NSMakePoint(NSMinX(screenFrame) + horizontalOffset,
                       NSMinY(screenFrame) + verticalOffset);
}

- (PETCharacterRuntimeController *)runtimeControllerForProfile:(PETPetProfile *)profile {
    PETCharacterRuntimeController *controller = self.runtimeControllers[profile.identifier];
    if (controller != nil) {
        return controller;
    }

    controller = [[PETCharacterRuntimeController alloc] initWithProfile:profile];
    NSDictionary<NSString *, id> *snapshot = self.characterSnapshots[profile.identifier];
    if (snapshot.count > 0) {
        [controller restoreFromSerializedSnapshot:snapshot];
    }
    self.runtimeControllers[profile.identifier] = controller;
    return controller;
}

- (void)persistRuntimeSnapshotForProfile:(PETPetProfile *)profile {
    PETCharacterRuntimeController *controller = self.runtimeControllers[profile.identifier];
    NSDictionary<NSString *, id> *snapshot = [controller serializedSnapshot];
    if (snapshot.count > 0) {
        self.characterSnapshots[profile.identifier] = snapshot;
    }
}

- (BOOL)realizePetProfileIfNeeded:(PETPetProfile *)profile {
    if (self.petWindows[profile.identifier] != nil) {
        return YES;
    }

    PETPetWindow *window = [[PETPetWindow alloc] initWithProfile:profile origin:[self defaultOriginForProfileCount:self.mutableProfiles.count]];
    if (window == nil) {
        return NO;
    }

    NSNumber *savedScale = self.petScales[profile.identifier];
    if (savedScale != nil) {
        [window applyScale:savedScale.doubleValue];
    }
    NSNumber *savedFacingDirection = self.petFacingDirections[profile.identifier];
    if (savedFacingDirection != nil) {
        [window applyFacingRight:savedFacingDirection.boolValue];
    }
    NSNumber *savedClickThrough = self.petClickThrough[profile.identifier];
    if (savedClickThrough != nil) {
        [window setClickThroughEnabled:savedClickThrough.boolValue];
    }

    [self applyCombatCharacterProfileIfNeeded:profile];

    self.petWindows[profile.identifier] = window;
    self.petScales[profile.identifier] = @(window.petScale);
    self.petFacingDirections[profile.identifier] = @(window.facingRight);
    self.petClickThrough[profile.identifier] = @(window.isClickThroughEnabled);
    PETCharacterRuntimeController *runtimeController = [self runtimeControllerForProfile:profile];
    [self.gameEngine registerPetWithProfile:profile runtimeController:runtimeController];
    NSDictionary<NSString *, id> *gameState = self.gameStates[profile.identifier];
    if (gameState.count > 0) {
        [self.gameEngine restorePetIdentifier:profile.identifier fromState:gameState];
        [self applyStoredGameStateToWindowIfPossible:gameState forPetProfile:profile];
    } else {
        [self.gameEngine setMovementPosition:[window stableFrameOrigin]
                                    bodySize:[window stableFrameSize]
                            forPetIdentifier:profile.identifier];
    }
    return YES;
}

- (void)unloadPetProfileIfNeeded:(PETPetProfile *)profile {
    [self persistRuntimeSnapshotForProfile:profile];
    NSDictionary<NSString *, id> *gameState = [self.gameEngine serializedStateForPetIdentifier:profile.identifier];
    if (gameState.count > 0) {
        self.gameStates[profile.identifier] = gameState;
    }
    [self.gameEngine removePetWithIdentifier:profile.identifier];

    PETPetWindow *window = self.petWindows[profile.identifier];
    [window close];
    [self.petWindows removeObjectForKey:profile.identifier];
    [self.runtimeControllers removeObjectForKey:profile.identifier];
}

- (instancetype)initWithConfiguration:(PETAppConfig *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _mutableProfiles = [NSMutableArray array];
        _petWindows = [NSMutableDictionary dictionary];
        _petScales = [NSMutableDictionary dictionary];
        _petFacingDirections = [NSMutableDictionary dictionary];
        _petClickThrough = [NSMutableDictionary dictionary];
        _runtimeControllers = [NSMutableDictionary dictionary];
        _characterSnapshots = [NSMutableDictionary dictionary];
        _gameStates = [NSMutableDictionary dictionary];
        _combatDebugSnapshots = [NSMutableDictionary dictionary];
        _lastCollisionSnapshots = [NSMutableDictionary dictionary];
        _hiddenProfileIdentifiers = [NSMutableSet set];
        _lastCognitionTimestamps = [NSMutableDictionary dictionary];
        _mergedCombatSkillResourcePaths = [NSMutableSet set];
        _gameEngine = [[PETGameEngine alloc] init];
        _keyboardInputRouter = [[PETKeyboardInputRouter alloc] init];
        _gamePresentationBridge = [[PETGamePresentationBridge alloc] init];
        __weak typeof(self) weakSelf = self;
        _keyboardInputRouter.petProvider = ^NSArray<NSString *> * _Nonnull{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            return [strongSelf controlledPetIdentifiersForKeyboardInput];
        };
        _keyboardInputRouter.commandHandler = ^(PETGameCommand *command) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf.gameEngine submitCommand:command];
        };
        NSError *combatBindingsError = nil;
        _combatKeyboardBindings = [[PETCombatKeyboardBindings alloc] initWithBundle:NSBundle.mainBundle
                                                                       skillLibrary:_gameEngine.skillLibrary
                                                                              error:&combatBindingsError];
        if (_combatKeyboardBindings == nil) {
            _combatKeyboardBindings = [PETCombatKeyboardBindings bindingsWithDefaultsValidatedBySkillLibrary:_gameEngine.skillLibrary];
        }
        _combatCharacterCatalog = [[PETCombatCharacterCatalog alloc] initWithBundle:NSBundle.mainBundle
                                                                       skillLibrary:_gameEngine.skillLibrary];
        _keyboardInputRouter.combatBindings = _combatKeyboardBindings;
        _keyboardInputRouter.combatCharacterCatalog = _combatCharacterCatalog;
        _keyboardInputRouter.combatProfileProvider = ^PETCombatCharacterProfile * _Nullable(NSString *petIdentifier) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            PETPetProfile *profile = [strongSelf profileForIdentifier:petIdentifier];
            if (profile == nil) {
                return nil;
            }
            PETCombatCharacterProfile *characterProfile = [strongSelf.combatCharacterCatalog profileForSourceURL:profile.sourceURL];
            if (characterProfile != nil) {
                return characterProfile;
            }
            return [strongSelf.combatCharacterCatalog loadProfileForSourceURL:profile.sourceURL
                                                                 skillLibrary:strongSelf.gameEngine.skillLibrary];
        };
        _keyboardInputRouter.petSourceURLProvider = ^NSURL * _Nullable(NSString *petIdentifier) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            PETPetProfile *profile = [strongSelf profileForIdentifier:petIdentifier];
            return profile.sourceURL;
        };
        _gamePresentationBridge.windowProvider = ^PETPetWindow * _Nullable(NSString *petIdentifier) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            return strongSelf.petWindows[petIdentifier];
        };
        _gamePresentationBridge.combatSnapshotProvider = ^NSDictionary<NSString *,id> * _Nullable(NSString *petIdentifier) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            return [strongSelf.gameEngine combatDebugSnapshotForPetIdentifier:petIdentifier] ?: strongSelf.combatDebugSnapshots[petIdentifier];
        };
        _gamePresentationBridge.movementCollisionEvaluator = ^NSDictionary<NSString *,id> * _Nullable(NSString *petIdentifier, CGPoint proposedOrigin, CGFloat sampleSpacing) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            PETPetWindow *sourceWindow = strongSelf.petWindows[petIdentifier];
            if (sourceWindow == nil) {
                return nil;
            }

            for (PETPetProfile *targetProfile in strongSelf.mutableProfiles) {
                if ([targetProfile.identifier isEqualToString:petIdentifier] || ![strongSelf isPetVisible:targetProfile]) {
                    continue;
                }
                PETPetWindow *targetWindow = strongSelf.petWindows[targetProfile.identifier];
                if (targetWindow == nil) {
                    continue;
                }

                NSPoint hitPoint = NSZeroPoint;
                if (![sourceWindow wouldIntersectPetWindowAtPixelLevel:targetWindow
                                                            fromOrigin:proposedOrigin
                                                         sampleSpacing:sampleSpacing
                                                              hitPoint:&hitPoint]) {
                    continue;
                }

                return @{
                    @"sourcePetIdentifier": petIdentifier ?: @"",
                    @"targetPetIdentifier": targetProfile.identifier ?: @"",
                    @"screenPoint": @{@"x": @(hitPoint.x), @"y": @(hitPoint.y)},
                    @"sampleSpacing": @(MAX(1.0, sampleSpacing))
                };
            }
            return nil;
        };
        _gameEngine.pixelCollisionEvaluator = ^NSDictionary<NSString *,id> * _Nullable(NSString *sourcePetIdentifier, NSString *targetPetIdentifier, CGFloat sampleSpacing) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            PETPetProfile *sourceProfile = [strongSelf profileForIdentifier:sourcePetIdentifier];
            PETPetProfile *targetProfile = [strongSelf profileForIdentifier:targetPetIdentifier];
            if (sourceProfile == nil || targetProfile == nil) {
                return nil;
            }
            return [strongSelf pixelCollisionSnapshotBetweenPetProfile:sourceProfile
                                                         andPetProfile:targetProfile
                                                         sampleSpacing:sampleSpacing];
        };
        _ocrService = [[PETOCRService alloc] init];
        NSURL *baseURL = [NSURL URLWithString:configuration.aiBaseURLString ?: @"https://api.openai.com/v1"];
        PETAIService *aiService = [[PETAIService alloc] initWithBaseURL:baseURL ?: [NSURL URLWithString:@"https://api.openai.com/v1"]];
        _cognitionEngine = [[PETStructuredCognitionEngine alloc] initWithAIService:aiService];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePetWindowRuntimeEvent:)
                                                     name:PETPetWindowDidEmitRuntimeEventNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePetWindowActivation:)
                                                     name:PETPetWindowDidActivateNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleGameEngineEvents:)
                                                     name:PETGameEngineDidEmitEventsNotification
                                                   object:_gameEngine];
        [self updateOCRMonitoringState];
        [self updateCognitionMonitoringState];
        [self updateKeyboardInputRouterState];
    }
    return self;
}

- (nullable PETPetProfile *)profileForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }
    for (PETPetProfile *profile in self.mutableProfiles) {
        if ([profile.identifier isEqualToString:identifier]) {
            return profile;
        }
    }
    return nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.keyboardInputRouter stop];
    [self.ocrPollingTimer invalidate];
    [self.cognitionPollingTimer invalidate];
}

- (NSArray<PETPetProfile *> *)activeProfiles {
    return self.mutableProfiles.copy;
}

- (void)refreshControlledPetWindowIndicatorsAnimated:(BOOL)animated {
    NSString *selectedIdentifier = self.selectedPetIdentifier;
    [self.petWindows enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull petIdentifier, PETPetWindow * _Nonnull window, BOOL * _Nonnull stop) {
        (void)stop;
        BOOL isSelected = (selectedIdentifier.length > 0 && [petIdentifier isEqualToString:selectedIdentifier]);
        [window setControlFocusActive:isSelected animated:(animated && isSelected)];
    }];
}

- (NSArray<NSString *> *)controlledPetIdentifiersForKeyboardInput {
    NSString *selectedIdentifier = self.selectedPetIdentifier;
    if (selectedIdentifier.length > 0 && [self.gameEngine.registeredPetIdentifiers containsObject:selectedIdentifier]) {
        return @[selectedIdentifier];
    }

    for (PETPetProfile *profile in self.mutableProfiles) {
        if (![self isPetVisible:profile]) {
            continue;
        }
        if ([self.gameEngine.registeredPetIdentifiers containsObject:profile.identifier]) {
            return @[profile.identifier];
        }
    }
    return @[];
}

- (void)setSelectedPetProfile:(PETPetProfile *)profile {
    NSString *identifier = profile.identifier;
    NSString *nextIdentifier = identifier.length > 0 ? [identifier copy] : nil;
    if ((self.selectedPetIdentifier == nil && nextIdentifier == nil) ||
        [self.selectedPetIdentifier isEqualToString:nextIdentifier]) {
        return;
    }
    self.selectedPetIdentifier = nextIdentifier;
    [self refreshControlledPetWindowIndicatorsAnimated:YES];
    [self notifyDidChange];
}

- (PETPetProfile *)selectedPetProfile {
    return [self profileForIdentifier:self.selectedPetIdentifier];
}

- (BOOL)isSoulArkCharacterProfile:(PETPetProfile *)profile {
    if ([profile.metadata[PETProfileMetadataSoulArkEnabledKey] boolValue]) {
        return YES;
    }
    NSString *stem = profile.sourceURL.lastPathComponent.stringByDeletingPathExtension.lowercaseString ?: @"";
    return [stem hasPrefix:@"char_"];
}

- (NSString *)combatSourceStemForProfile:(PETPetProfile *)profile {
    NSString *stem = profile.sourceURL.lastPathComponent.stringByDeletingPathExtension ?: @"";
    return stem.length > 0 ? stem : @"";
}

- (nullable NSURL *)bundleCompanionSkillURLForProfile:(PETPetProfile *)profile {
    NSString *stem = [self combatSourceStemForProfile:profile];
    if (stem.length == 0) {
        return nil;
    }

    NSString *relativePath = [NSString stringWithFormat:@"Skills/%@.skills-munjoong.json", stem];
    return PETPetManagerFindBundledResourceURL(relativePath);
}

- (BOOL)mergeSkillLibraryFromJSONURL:(NSURL *)jsonURL error:(NSError * _Nullable * _Nullable)error {
    if (self.gameEngine.skillLibrary == nil || jsonURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetManager" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Skill library is unavailable."}];
        }
        return NO;
    }
    return [self.gameEngine.skillLibrary mergeFromJSONURL:jsonURL error:error];
}

- (void)mergeSkillLibraryFromURLIfNeeded:(NSURL *)url logLabel:(NSString *)logLabel {
    if (self.gameEngine.skillLibrary == nil || url == nil) {
        return;
    }

    NSString *resourcePath = url.path ?: @"";
    if (resourcePath.length == 0 || [self.mergedCombatSkillResourcePaths containsObject:resourcePath]) {
        return;
    }

    NSError *mergeError = nil;
    if ([self.gameEngine.skillLibrary mergeFromJSONURL:url error:&mergeError]) {
        [self.mergedCombatSkillResourcePaths addObject:resourcePath];
        if (logLabel.length > 0) {
            NSLog(@"[DesktopPet] Merged %@ from %@", logLabel, resourcePath);
        }
    } else if (mergeError != nil) {
        NSLog(@"[DesktopPet] Failed to merge %@ from %@: %@", logLabel ?: @"combat skills", resourcePath, mergeError.localizedDescription);
    }
}

- (void)mergeCombatSkillsForProfileIfNeeded:(PETPetProfile *)profile {
    if (self.gameEngine.skillLibrary == nil) {
        return;
    }

    if ([self isSoulArkCharacterProfile:profile]) {
        NSURL *bundleSoulArkSkillsURL = PETPetManagerFindBundledResourceURL(@"Skills/skills-soul-ark.json");
        [self mergeSkillLibraryFromURLIfNeeded:bundleSoulArkSkillsURL logLabel:@"bundle combat skills"];
    }

    NSURL *bundleCompanionURL = [self bundleCompanionSkillURLForProfile:profile];
    [self mergeSkillLibraryFromURLIfNeeded:bundleCompanionURL logLabel:@"bundle companion combat skills"];

    NSURL *directoryURL = profile.sourceURL.URLByDeletingLastPathComponent;
    NSArray<NSString *> *candidateNames = @[@"skills-munjoong.json", @"skills.json", @"combat-skills.json", @"skills-soul-ark.json"];
    for (NSString *candidateName in candidateNames) {
        NSURL *candidateURL = [directoryURL URLByAppendingPathComponent:candidateName];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidateURL.path]) {
            continue;
        }
        [self mergeSkillLibraryFromURLIfNeeded:candidateURL logLabel:@"combat skills"];
    }
}

- (void)applyCombatCharacterProfileIfNeeded:(PETPetProfile *)profile {
    [self mergeCombatSkillsForProfileIfNeeded:profile];

    PETCombatCharacterProfile *characterProfile = [self.combatCharacterCatalog loadProfileForSourceURL:profile.sourceURL
                                                                                          skillLibrary:self.gameEngine.skillLibrary];
    if (characterProfile == nil) {
        characterProfile = [self.combatCharacterCatalog profileForSourceURL:profile.sourceURL];
    }
    if (characterProfile == nil) {
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *baseAliases = [[profile baseInteractionAliases] mutableCopy] ?: [NSMutableDictionary dictionary];
    [characterProfile.interactionAliases enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull state, BOOL * _Nonnull stop) {
        (void)stop;
        if (state.length > 0) {
            baseAliases[key] = state;
        }
    }];
    [profile setMetadataValue:baseAliases.copy forKey:@"baseInteractionAliases"];
}

- (BOOL)addPetProfile:(PETPetProfile *)profile error:(NSError **)error {
    PETPetProfile *existingProfile = [self profileMatchingSourceURL:profile.sourceURL];
    if (existingProfile != nil) {
        [self removePetProfile:existingProfile];
    }

    [self applyCombatCharacterProfileIfNeeded:profile];

    BOOL shouldShowImmediately = (self.visiblePetCount < (NSUInteger)self.configuration.maxConcurrentPets);
    [self.mutableProfiles addObject:profile];
    if (shouldShowImmediately) {
        [self.hiddenProfileIdentifiers removeObject:profile.identifier];
        if (![self realizePetProfileIfNeeded:profile]) {
            [self.mutableProfiles removeObject:profile];
            if (error != NULL) {
                *error = [NSError errorWithDomain:@"PETPetManager"
                                             code:4002
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unable to create the pet window."}];
            }
            return NO;
        }
        [self.petWindows[profile.identifier] orderFrontRegardless];
    } else {
        [self.hiddenProfileIdentifiers addObject:profile.identifier];
    }

    if (self.selectedPetIdentifier.length == 0) {
        self.selectedPetIdentifier = profile.identifier;
    }

    [self notifyDidChange];
    return YES;
}

- (BOOL)isPetVisible:(PETPetProfile *)profile {
    return ![self.hiddenProfileIdentifiers containsObject:profile.identifier];
}

- (void)setVisibility:(BOOL)isVisible forPetProfile:(PETPetProfile *)profile {
    if (isVisible) {
        if (![self isPetVisible:profile] && self.visiblePetCount >= (NSUInteger)self.configuration.maxConcurrentPets) {
            PETPetProfile *profileToHide = [self firstVisibleProfileExcludingProfile:profile];
            if (profileToHide != nil) {
                [self.hiddenProfileIdentifiers addObject:profileToHide.identifier];
                [self unloadPetProfileIfNeeded:profileToHide];
                if ([profileToHide.identifier isEqualToString:self.selectedPetIdentifier]) {
                    self.selectedPetIdentifier = profile.identifier;
                }
            }
        }
        [self.hiddenProfileIdentifiers removeObject:profile.identifier];
        if ([self realizePetProfileIfNeeded:profile]) {
            [self.petWindows[profile.identifier] orderFrontRegardless];
        }
        if (self.selectedPetIdentifier.length == 0) {
            self.selectedPetIdentifier = profile.identifier;
        }
    } else {
        [self.hiddenProfileIdentifiers addObject:profile.identifier];
        [self unloadPetProfileIfNeeded:profile];
        if ([profile.identifier isEqualToString:self.selectedPetIdentifier]) {
            self.selectedPetIdentifier = [self firstVisibleProfileExcludingProfile:profile].identifier ?: self.mutableProfiles.firstObject.identifier;
        }
    }

    [self notifyDidChange];
}

- (CGFloat)scaleForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    if (window != nil) {
        return window.petScale;
    }
    NSNumber *storedValue = self.petScales[profile.identifier];
    return storedValue != nil ? storedValue.doubleValue : PETPetManagerDefaultScale;
}

- (void)setScale:(CGFloat)scale forPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    [window applyScale:scale];
    self.petScales[profile.identifier] = @(window != nil ? window.petScale : scale);
    [self notifyDidChange];
}

- (BOOL)isFacingRightForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    if (window != nil) {
        return window.facingRight;
    }
    NSNumber *storedValue = self.petFacingDirections[profile.identifier];
    return storedValue != nil ? storedValue.boolValue : YES;
}

- (void)setFacingRight:(BOOL)facingRight forPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    [window applyUserFacingRight:facingRight];
    self.petFacingDirections[profile.identifier] = @(window != nil ? window.facingRight : facingRight);
    [self notifyDidChange];
}

- (BOOL)isClickThroughEnabledForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    if (window != nil) {
        return window.isClickThroughEnabled;
    }
    NSNumber *storedValue = self.petClickThrough[profile.identifier];
    return storedValue.boolValue;
}

- (void)setClickThroughEnabled:(BOOL)isEnabled forPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    [window setClickThroughEnabled:isEnabled];
    self.petClickThrough[profile.identifier] = @(isEnabled);
    [self notifyDidChange];
}

- (BOOL)isSoulArkEnabledForPetProfile:(PETPetProfile *)profile {
    return [profile.metadata[PETProfileMetadataSoulArkEnabledKey] boolValue];
}

- (void)setSoulArkEnabled:(BOOL)isEnabled forPetProfile:(PETPetProfile *)profile {
    [profile setMetadataValue:@(isEnabled) forKey:PETProfileMetadataSoulArkEnabledKey];
    [self refreshMovementPresentationForPetProfile:profile];
    [self notifyDidChange];
}

- (BOOL)isSoulArkFacingInvertedForPetProfile:(PETPetProfile *)profile {
    return [profile.metadata[PETProfileMetadataSoulArkFacingInvertedKey] boolValue];
}

- (void)setSoulArkFacingInverted:(BOOL)isInverted forPetProfile:(PETPetProfile *)profile {
    [profile setMetadataValue:@(isInverted) forKey:PETProfileMetadataSoulArkFacingInvertedKey];
    [self refreshMovementPresentationForPetProfile:profile];
    [self notifyDidChange];
}

- (NSArray<NSString *> *)supportedStatesForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    if (window != nil) {
        return window.supportedStates;
    }
    return profile.supportedStates;
}

- (NSString *)currentStateForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    if (window != nil) {
        return window.currentState ?: profile.defaultState;
    }
    return profile.defaultState;
}

- (NSDictionary<NSString *,id> *)characterSnapshotForPetProfile:(PETPetProfile *)profile {
    PETCharacterRuntimeController *controller = self.runtimeControllers[profile.identifier];
    NSDictionary<NSString *, id> *snapshot = [controller serializedSnapshot];
    if (snapshot.count > 0) {
        self.characterSnapshots[profile.identifier] = snapshot;
        return snapshot;
    }
    return self.characterSnapshots[profile.identifier] ?: @{};
}

- (NSDictionary<NSString *,id> *)gameStateForPetProfile:(PETPetProfile *)profile {
    NSDictionary<NSString *, id> *gameState = [self.gameEngine serializedStateForPetIdentifier:profile.identifier];
    if (gameState.count > 0) {
        self.gameStates[profile.identifier] = gameState;
        return gameState;
    }
    return self.gameStates[profile.identifier] ?: @{};
}

- (NSDictionary<NSString *,id> *)combatDebugSnapshotForPetProfile:(PETPetProfile *)profile {
    NSDictionary<NSString *, id> *snapshot = [self.gameEngine combatDebugSnapshotForPetIdentifier:profile.identifier];
    if (snapshot.count > 0) {
        self.combatDebugSnapshots[profile.identifier] = snapshot;
        return snapshot;
    }
    return self.combatDebugSnapshots[profile.identifier] ?: @{};
}

- (NSDictionary<NSString *,id> *)lastCollisionSnapshotForPetProfile:(PETPetProfile *)profile {
    return self.lastCollisionSnapshots[profile.identifier];
}

- (NSArray<NSDictionary<NSString *,id> *> *)recentGameEvents {
    NSMutableArray<NSDictionary<NSString *, id> *> *events = [NSMutableArray arrayWithCapacity:self.gameEngine.recentEvents.count];
    for (PETGameEvent *event in self.gameEngine.recentEvents) {
        [events addObject:[event dictionaryRepresentation]];
    }
    return events.copy;
}

- (NSString *)characterRuntimeSummaryForPetProfile:(PETPetProfile *)profile {
    PETCharacterRuntimeController *controller = self.runtimeControllers[profile.identifier];
    if (controller == nil) {
        return [self.hiddenProfileIdentifiers containsObject:profile.identifier]
            ? @"Hidden | Runtime unloaded"
            : @"Intent ambient.exist | Emotion calm | Behavior idle | Animation idle";
    }
    return [controller runtimeSummary] ?: @"Intent ambient.exist | Emotion calm | Behavior idle | Animation idle";
}

- (void)restoreCharacterSnapshot:(NSDictionary<NSString *,id> *)snapshot forPetProfile:(PETPetProfile *)profile {
    self.characterSnapshots[profile.identifier] = snapshot ?: @{};
    PETCharacterRuntimeController *controller = self.runtimeControllers[profile.identifier];
    [controller restoreFromSerializedSnapshot:snapshot];
    [self notifyDidChange];
}

- (void)restoreGameState:(NSDictionary<NSString *,id> *)state forPetProfile:(PETPetProfile *)profile {
    self.gameStates[profile.identifier] = state ?: @{};
    [self.gameEngine restorePetIdentifier:profile.identifier fromState:state ?: @{}];
    [self applyStoredGameStateToWindowIfPossible:state forPetProfile:profile];
    [self notifyDidChange];
}

- (void)submitGameCommand:(PETGameCommand *)command {
    [self.gameEngine submitCommand:command];
}

- (void)previewState:(NSString *)state forPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    [[self runtimeControllerForProfile:profile] previewAnimationState:state];
    [window previewState:state];
    [self notifyDidChange];
}

- (void)resumeAmbientBehaviorForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    [[self runtimeControllerForProfile:profile] resumeAmbientBehavior];
    [window resumeAmbientBehavior];
    [self notifyDidChange];
}

- (NSDictionary<NSString *,NSString *> *)interactionAliasesForPetProfile:(PETPetProfile *)profile {
    return profile.interactionAliases ?: @{};
}

- (void)setInteractionAlias:(NSString *)animationState forActionKey:(NSString *)actionKey forPetProfile:(PETPetProfile *)profile {
    [profile setInteractionAlias:animationState forActionKey:actionKey];
    [self notifyDidChange];
}

- (void)renamePetProfile:(PETPetProfile *)profile displayName:(NSString *)displayName {
    NSString *trimmedName = [displayName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    profile.displayName = trimmedName.length > 0 ? trimmedName : @"Pet";
    [self notifyDidChange];
}

- (void)removePetProfile:(PETPetProfile *)profile {
    BOOL removedSelectedProfile = [profile.identifier isEqualToString:self.selectedPetIdentifier];
    [self unloadPetProfileIfNeeded:profile];
    [self.petScales removeObjectForKey:profile.identifier];
    [self.petFacingDirections removeObjectForKey:profile.identifier];
    [self.petClickThrough removeObjectForKey:profile.identifier];
    [self.characterSnapshots removeObjectForKey:profile.identifier];
    [self.gameStates removeObjectForKey:profile.identifier];
    [self.combatDebugSnapshots removeObjectForKey:profile.identifier];
    [self.lastCollisionSnapshots removeObjectForKey:profile.identifier];
    [self.hiddenProfileIdentifiers removeObject:profile.identifier];
    [self.mutableProfiles removeObject:profile];
    if (removedSelectedProfile) {
        self.selectedPetIdentifier = [self firstVisibleProfileExcludingProfile:nil].identifier ?: self.mutableProfiles.firstObject.identifier;
    }
    [self notifyDidChange];
}

- (void)setAllPetsHidden:(BOOL)hidden {
    for (PETPetProfile *profile in self.mutableProfiles) {
        [self setVisibility:!hidden forPetProfile:profile];
    }
    if (hidden) {
        self.selectedPetIdentifier = nil;
    } else if (self.selectedPetIdentifier.length == 0) {
        self.selectedPetIdentifier = [self firstVisibleProfileExcludingProfile:nil].identifier;
    }
}

- (void)removeAllPets {
    for (PETPetProfile *profile in self.mutableProfiles) {
        [self unloadPetProfileIfNeeded:profile];
    }
    [self.mutableProfiles removeAllObjects];
    [self.petWindows removeAllObjects];
    [self.petScales removeAllObjects];
    [self.petFacingDirections removeAllObjects];
    [self.petClickThrough removeAllObjects];
    [self.runtimeControllers removeAllObjects];
    [self.characterSnapshots removeAllObjects];
    [self.gameStates removeAllObjects];
    [self.combatDebugSnapshots removeAllObjects];
    [self.lastCollisionSnapshots removeAllObjects];
    [self.hiddenProfileIdentifiers removeAllObjects];
    self.selectedPetIdentifier = nil;
    [self.gameEngine removeAllPets];
    [self notifyDidChange];
}

- (NSArray<NSDictionary<NSString *, id> *> *)serializedPetRecords {
    NSMutableArray<NSDictionary<NSString *, id> *> *records = [NSMutableArray arrayWithCapacity:self.mutableProfiles.count];
    for (PETPetProfile *profile in self.mutableProfiles) {
        NSString *sourcePath = profile.sourceURL.path;
        if (sourcePath.length == 0) {
            continue;
        }

        NSDictionary<NSString *, id> *gameState = [self.gameEngine serializedStateForPetIdentifier:profile.identifier] ?: self.gameStates[profile.identifier] ?: @{};
        if (gameState.count > 0) {
            self.gameStates[profile.identifier] = gameState;
        }

        NSDictionary<NSString *, id> *record = @{
            @"sourcePath": sourcePath,
            @"displayName": profile.displayName ?: @"Pet",
            @"scale": @([self scaleForPetProfile:profile]),
            @"facingRight": @([self isFacingRightForPetProfile:profile]),
            @"clickThrough": @([self isClickThroughEnabledForPetProfile:profile]),
            @"visible": @([self isPetVisible:profile]),
            @"profileMetadataOverrides": @{
                PETProfileMetadataSoulArkEnabledKey: @([self isSoulArkEnabledForPetProfile:profile]),
                PETProfileMetadataSoulArkFacingInvertedKey: @([self isSoulArkFacingInvertedForPetProfile:profile])
            },
            @"interactionAliases": profile.interactionAliases ?: @{},
            @"characterSnapshot": [self characterSnapshotForPetProfile:profile] ?: @{},
            @"gameState": gameState ?: @{}
        };
        [records addObject:record];
    }
    return records.copy;
}

- (NSDictionary<NSString *, id> *)pixelCollisionSnapshotBetweenPetProfile:(PETPetProfile *)sourceProfile
                                                             andPetProfile:(PETPetProfile *)targetProfile
                                                             sampleSpacing:(CGFloat)sampleSpacing {
    PETPetWindow *sourceWindow = self.petWindows[sourceProfile.identifier];
    PETPetWindow *targetWindow = self.petWindows[targetProfile.identifier];
    if (sourceWindow == nil || targetWindow == nil) {
        return nil;
    }

    NSPoint sourceStableOrigin = [self stableMovementOriginForPetIdentifier:sourceProfile.identifier fallbackWindow:sourceWindow];
    NSPoint targetStableOrigin = [self stableMovementOriginForPetIdentifier:targetProfile.identifier fallbackWindow:targetWindow];
    NSPoint sourceOrigin = [sourceWindow presentedFrameOriginForStableOrigin:sourceStableOrigin];
    NSPoint targetOrigin = [targetWindow presentedFrameOriginForStableOrigin:targetStableOrigin];
    NSPoint hitPoint = NSZeroPoint;
    NSString *collisionMethod = @"pixelOverlap";
    BOOL collided = [sourceWindow wouldIntersectPetWindowAtPixelLevel:targetWindow
                                                           fromOrigin:sourceOrigin
                                                          otherOrigin:targetOrigin
                                                        sampleSpacing:sampleSpacing
                                                             hitPoint:&hitPoint];
    if (!collided) {
        CGSize sourceStableSize = [sourceWindow stableFrameSize];
        CGSize targetStableSize = [targetWindow stableFrameSize];
        BOOL sourceUsesExpandedFrame = fabs(sourceWindow.frame.size.width - sourceStableSize.width) > 0.5 ||
                                       fabs(sourceWindow.frame.size.height - sourceStableSize.height) > 0.5;
        BOOL targetUsesExpandedFrame = fabs(targetWindow.frame.size.width - targetStableSize.width) > 0.5 ||
                                       fabs(targetWindow.frame.size.height - targetStableSize.height) > 0.5;
        if (!sourceUsesExpandedFrame && !targetUsesExpandedFrame) {
            return nil;
        }

        NSRect sourceVisibleRect = [sourceWindow visibleRenderedContentRectAtScreenOrigin:sourceOrigin];
        NSRect targetVisibleRect = [targetWindow visibleRenderedContentRectAtScreenOrigin:targetOrigin];
        NSRect visibleOverlap = NSIntersectionRect(sourceVisibleRect, targetVisibleRect);
        CGFloat overlapArea = visibleOverlap.size.width * visibleOverlap.size.height;
        CGFloat minimumOverlapArea = MAX(36.0, MAX(1.0, sampleSpacing) * MAX(1.0, sampleSpacing));
        if (NSIsEmptyRect(visibleOverlap) || overlapArea < minimumOverlapArea) {
            return nil;
        }

        hitPoint = NSMakePoint(NSMidX(visibleOverlap), NSMidY(visibleOverlap));
        collided = YES;
        collisionMethod = @"visibleRectFallback";
    }

    return @{
        @"sourcePetIdentifier": sourceProfile.identifier ?: @"",
        @"targetPetIdentifier": targetProfile.identifier ?: @"",
        @"sourceOrigin": @{@"x": @(sourceStableOrigin.x), @"y": @(sourceStableOrigin.y)},
        @"targetOrigin": @{@"x": @(targetStableOrigin.x), @"y": @(targetStableOrigin.y)},
        @"screenPoint": @{@"x": @(hitPoint.x), @"y": @(hitPoint.y)},
        @"sampleSpacing": @(MAX(1.0, sampleSpacing)),
        @"collisionMethod": collisionMethod
    };
}

- (NSPoint)stableMovementOriginForPetIdentifier:(NSString *)petIdentifier fallbackWindow:(PETPetWindow *)window {
    NSDictionary<NSString *, id> *gameState = [self.gameEngine serializedStateForPetIdentifier:petIdentifier] ?: self.gameStates[petIdentifier];
    NSDictionary<NSString *, id> *movement = [gameState[@"movement"] isKindOfClass:NSDictionary.class] ? gameState[@"movement"] : nil;
    NSDictionary<NSString *, id> *position = [movement[@"position"] isKindOfClass:NSDictionary.class] ? movement[@"position"] : nil;
    if (position != nil) {
        return NSMakePoint([position[@"x"] doubleValue], [position[@"y"] doubleValue]);
    }
    return window != nil ? [window stableFrameOrigin] : NSZeroPoint;
}

- (void)handlePetWindowRuntimeEvent:(NSNotification *)notification {
    NSDictionary<NSString *, id> *userInfo = notification.userInfo;
    NSString *profileIdentifier = [userInfo[PETPetWindowProfileIdentifierUserInfoKey] isKindOfClass:NSString.class] ? userInfo[PETPetWindowProfileIdentifierUserInfoKey] : nil;
    NSString *actionKey = [userInfo[PETPetWindowActionKeyUserInfoKey] isKindOfClass:NSString.class] ? userInfo[PETPetWindowActionKeyUserInfoKey] : nil;
    NSString *fallbackBehaviorState = [userInfo[PETPetWindowFallbackBehaviorStateUserInfoKey] isKindOfClass:NSString.class] ? userInfo[PETPetWindowFallbackBehaviorStateUserInfoKey] : nil;
    NSString *resolvedAnimationState = [userInfo[PETPetWindowResolvedAnimationStateUserInfoKey] isKindOfClass:NSString.class] ? userInfo[PETPetWindowResolvedAnimationStateUserInfoKey] : nil;
    NSString *mode = [userInfo[PETPetWindowRuntimeModeUserInfoKey] isKindOfClass:NSString.class] ? userInfo[PETPetWindowRuntimeModeUserInfoKey] : nil;
    if (profileIdentifier.length == 0 || resolvedAnimationState.length == 0) {
        return;
    }

    PETCharacterRuntimeController *controller = self.runtimeControllers[profileIdentifier];
    if (controller == nil) {
        return;
    }

    NSMutableDictionary<NSString *, id> *context = [NSMutableDictionary dictionary];
    if (mode.length > 0) {
        context[@"runtimeMode"] = mode;
    }
    [controller recordActionKey:actionKey ?: @"runtime.react"
          fallbackBehaviorState:fallbackBehaviorState
         resolvedAnimationState:resolvedAnimationState
                        context:context.copy];
    [self notifyDidChange];
}

- (void)handlePetWindowActivation:(NSNotification *)notification {
    NSDictionary<NSString *, id> *userInfo = notification.userInfo;
    NSString *profileIdentifier = [userInfo[PETPetWindowProfileIdentifierUserInfoKey] isKindOfClass:NSString.class] ? userInfo[PETPetWindowProfileIdentifierUserInfoKey] : nil;
    PETPetProfile *profile = [self profileForIdentifier:profileIdentifier];
    if (profile == nil) {
        return;
    }
    [self setSelectedPetProfile:profile];
}

- (void)notifyDidChange {
    [self refreshControlledPetWindowIndicatorsAnimated:NO];
    [self updateOCRMonitoringState];
    [self updateCognitionMonitoringState];
    [self updateKeyboardInputRouterState];
    [[NSNotificationCenter defaultCenter] postNotificationName:PETPetManagerDidChangePetsNotification object:self];
}

- (void)handleGameEngineEvents:(NSNotification *)notification {
    NSArray<PETGameEvent *> *events = [notification.userInfo[PETGameEngineEventsUserInfoKey] isKindOfClass:NSArray.class] ? notification.userInfo[PETGameEngineEventsUserInfoKey] : @[];
    [self.gamePresentationBridge applyGameEvents:events];
    NSMutableSet<NSString *> *debugChangedPetIdentifiers = [NSMutableSet set];
    for (PETGameEvent *event in events) {
        if ([event.eventType isEqualToString:PETGameEventAttackHit]) {
            NSDictionary<NSString *, id> *collisionSnapshot = [event.context[@"collisionSnapshot"] isKindOfClass:NSDictionary.class] ? event.context[@"collisionSnapshot"] : nil;
            if (collisionSnapshot.count > 0) {
                NSMutableDictionary<NSString *, id> *enrichedCollisionSnapshot = [collisionSnapshot mutableCopy];
                enrichedCollisionSnapshot[@"timestamp"] = @([event.timestamp timeIntervalSince1970]);
                if ([event.context[@"attackIdentifier"] isKindOfClass:NSString.class]) {
                    enrichedCollisionSnapshot[@"attackIdentifier"] = event.context[@"attackIdentifier"];
                }
                if ([event.context[@"attackKind"] isKindOfClass:NSString.class]) {
                    enrichedCollisionSnapshot[@"attackKind"] = event.context[@"attackKind"];
                }
                self.lastCollisionSnapshots[event.petIdentifier] = enrichedCollisionSnapshot.copy;
                NSString *targetPetIdentifier = [event.context[@"targetPetIdentifier"] isKindOfClass:NSString.class] ? event.context[@"targetPetIdentifier"] : nil;
                if (targetPetIdentifier.length > 0) {
                    self.lastCollisionSnapshots[targetPetIdentifier] = enrichedCollisionSnapshot.copy;
                    [debugChangedPetIdentifiers addObject:targetPetIdentifier];
                }
                [debugChangedPetIdentifiers addObject:event.petIdentifier ?: @""];
            }
        }
        if ([event.eventType hasPrefix:@"game.combat."] || [event.eventType hasPrefix:@"game.attack."]) {
            NSDictionary<NSString *, id> *snapshot = [self.gameEngine combatDebugSnapshotForPetIdentifier:event.petIdentifier];
            if (snapshot.count > 0) {
                self.combatDebugSnapshots[event.petIdentifier] = snapshot;
                [debugChangedPetIdentifiers addObject:event.petIdentifier ?: @""];
            }
        }
        if (![event.eventType hasPrefix:@"game.move."]) {
            continue;
        }
        if ([event.source isEqualToString:@"game.skill.motion"]) {
            continue;
        }
        PETPetWindow *window = self.petWindows[event.petIdentifier];
        if (window == nil) {
            continue;
        }
        [self.gameEngine setMovementPosition:[window stableFrameOrigin]
                                    bodySize:[window stableFrameSize]
                            forPetIdentifier:event.petIdentifier];
    }
    [debugChangedPetIdentifiers removeObject:@""];
    if (debugChangedPetIdentifiers.count > 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:PETPetManagerDidUpdateRuntimeDebugNotification object:self];
    }
}

- (void)updateKeyboardInputRouterState {
    if (self.petWindows.count > 0 || self.gameEngine.registeredPetIdentifiers.count > 0) {
        [self.keyboardInputRouter start];
    } else {
        [self.keyboardInputRouter stop];
    }
}

- (void)applyStoredGameStateToWindowIfPossible:(NSDictionary<NSString *, id> *)gameState forPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    NSDictionary<NSString *, id> *movement = [gameState[@"movement"] isKindOfClass:NSDictionary.class] ? gameState[@"movement"] : nil;
    NSDictionary<NSString *, id> *position = [movement[@"position"] isKindOfClass:NSDictionary.class] ? movement[@"position"] : nil;
    if (window == nil || position == nil) {
        return;
    }
    NSPoint origin = NSMakePoint([position[@"x"] doubleValue], [position[@"y"] doubleValue]);
    [window setFrameOrigin:[window presentedFrameOriginForStableOrigin:origin]];
    [self.gameEngine setMovementPosition:origin bodySize:[window stableFrameSize] forPetIdentifier:profile.identifier];
}

- (void)refreshMovementPresentationForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    if (window == nil) {
        return;
    }

    NSDictionary<NSString *, id> *gameState = [self.gameEngine serializedStateForPetIdentifier:profile.identifier] ?: self.gameStates[profile.identifier];
    NSDictionary<NSString *, id> *movement = [gameState[@"movement"] isKindOfClass:NSDictionary.class] ? gameState[@"movement"] : nil;
    NSString *movementState = [movement[@"movementState"] isKindOfClass:NSString.class] ? movement[@"movementState"] : nil;
    NSString *facingDirection = [movement[@"facingDirection"] isKindOfClass:NSString.class] ? movement[@"facingDirection"] : nil;
    BOOL facingRight = ![facingDirection isEqualToString:@"left"];

    if (movementState.length > 0) {
        [window applyGameMovementState:movementState facingRight:facingRight];
        return;
    }

    [window applyFacingRight:[self isFacingRightForPetProfile:profile]];
}

- (void)updateOCRMonitoringState {
    BOOL shouldRunOCR = self.configuration.OCRDesktopEnabled && self.mutableProfiles.count > 0;
    if (shouldRunOCR && self.ocrPollingTimer == nil) {
        self.ocrPollingTimer = [NSTimer scheduledTimerWithTimeInterval:12.0
                                                                target:self
                                                              selector:@selector(handleOCRPollingTimer:)
                                                              userInfo:nil
                                                               repeats:YES];
        [self.ocrPollingTimer fire];
        return;
    }
    if (!shouldRunOCR && self.ocrPollingTimer != nil) {
        [self.ocrPollingTimer invalidate];
        self.ocrPollingTimer = nil;
        self.lastOCRSignature = nil;
    }
}

- (void)handleOCRPollingTimer:(NSTimer *)timer {
    (void)timer;
    if (!self.configuration.OCRDesktopEnabled || self.mutableProfiles.count == 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.ocrService captureDesktopAndRecognizeWithCompletion:^(NSArray<NSString *> *recognizedLines, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || error != nil || recognizedLines.count == 0) {
            return;
        }
        [strongSelf propagateRecognizedLinesIntoRuntime:recognizedLines];
    }];
}

- (void)updateCognitionMonitoringState {
    BOOL shouldRun = self.configuration.cognitionEnabled && self.mutableProfiles.count > 0;
    if (shouldRun && self.cognitionPollingTimer == nil) {
        self.cognitionPollingTimer = [NSTimer scheduledTimerWithTimeInterval:20.0
                                                                      target:self
                                                                    selector:@selector(handleCognitionPollingTimer:)
                                                                    userInfo:nil
                                                                     repeats:YES];
        [self.cognitionPollingTimer fire];
        return;
    }
    if (!shouldRun && self.cognitionPollingTimer != nil) {
        [self.cognitionPollingTimer invalidate];
        self.cognitionPollingTimer = nil;
        [self.lastCognitionTimestamps removeAllObjects];
    }
}

- (void)handleCognitionPollingTimer:(NSTimer *)timer {
    (void)timer;
    if (!self.configuration.cognitionEnabled) {
        return;
    }
    for (PETPetProfile *profile in self.mutableProfiles) {
        if (![self isPetVisible:profile]) {
            continue;
        }
        [self requestCognitionForProfileIfNeeded:profile];
    }
}

- (void)requestCognitionForProfileIfNeeded:(PETPetProfile *)profile {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval lastTimestamp = [self.lastCognitionTimestamps[profile.identifier] doubleValue];
    if (lastTimestamp > 0.0 && (now - lastTimestamp) < 18.0) {
        return;
    }
    self.lastCognitionTimestamps[profile.identifier] = @(now);

    PETCharacterRuntimeController *controller = [self runtimeControllerForProfile:profile];
    __weak typeof(self) weakSelf = self;
    [self.cognitionEngine requestSuggestionForSnapshot:controller.currentSnapshot completion:^(PETStructuredCognitionSuggestion * _Nullable suggestion, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || suggestion == nil || error != nil) {
            return;
        }
        PETCharacterRuntimeController *liveController = [strongSelf runtimeControllerForProfile:profile];
        [liveController applyStructuredCognitionSuggestion:suggestion];
        [strongSelf notifyDidChange];
    }];
}

- (void)propagateRecognizedLinesIntoRuntime:(NSArray<NSString *> *)recognizedLines {
    NSString *signature = [recognizedLines componentsJoinedByString:@"\n"];
    if (signature.length == 0 || [signature isEqualToString:self.lastOCRSignature]) {
        return;
    }
    self.lastOCRSignature = signature;

    for (PETPetProfile *profile in self.mutableProfiles) {
        if (![self isPetVisible:profile]) {
            continue;
        }
        PETCharacterRuntimeController *controller = [self runtimeControllerForProfile:profile];
        NSString *resolvedAnimationState = [self currentStateForPetProfile:profile] ?: profile.defaultState;
        NSMutableDictionary<NSString *, id> *context = [NSMutableDictionary dictionary];
        context[@"runtimeMode"] = @"perception";
        context[@"perceptionSource"] = @"desktop.ocr";
        context[@"recognizedLines"] = recognizedLines;
        context[@"recognizedText"] = signature;
        context[@"recognizedLineCount"] = @(recognizedLines.count);
        [controller recordActionKey:@"perception.ocr.text"
              fallbackBehaviorState:@"waiting"
             resolvedAnimationState:resolvedAnimationState.length > 0 ? resolvedAnimationState : profile.defaultState
                            context:context.copy];
    }
    [self notifyDidChange];
}

@end
