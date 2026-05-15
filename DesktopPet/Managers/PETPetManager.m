#import "PETPetManager.h"

#import "../Config/PETAppConfig.h"
#import "../Models/PETPetProfile.h"
#import "../Models/PETStructuredCognitionSuggestion.h"
#import "../Services/PETAIService.h"
#import "../Services/PETCharacterRuntimeController.h"
#import "../Services/PETOCRService.h"
#import "../Services/PETStructuredCognitionEngine.h"
#import "../UI/PETPetWindow.h"

NSNotificationName const PETPetManagerDidChangePetsNotification = @"PETPetManagerDidChangePetsNotification";

@interface PETPetManager ()

@property (nonatomic, strong) PETAppConfig *configuration;
@property (nonatomic, strong) NSMutableArray<PETPetProfile *> *mutableProfiles;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PETPetWindow *> *petWindows;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *petScales;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *petFacingDirections;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *petClickThrough;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PETCharacterRuntimeController *> *runtimeControllers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *characterSnapshots;
@property (nonatomic, strong) NSMutableSet<NSString *> *hiddenProfileIdentifiers;
@property (nonatomic, strong) PETStructuredCognitionEngine *cognitionEngine;
@property (nonatomic, strong) PETOCRService *ocrService;
@property (nonatomic, strong) NSTimer *ocrPollingTimer;
@property (nonatomic, strong) NSTimer *cognitionPollingTimer;
@property (nonatomic, copy) NSString *lastOCRSignature;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastCognitionTimestamps;

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

- (CGPoint)defaultOriginForProfileCount:(NSUInteger)profileCount {
    NSScreen *screen = NSScreen.mainScreen;
    NSRect visibleFrame = screen.visibleFrame;
    CGFloat horizontalOffset = 24.0 + (CGFloat)(profileCount * 40);
    CGFloat verticalOffset = 48.0 + (CGFloat)(profileCount * 24);
    return NSMakePoint(NSMinX(visibleFrame) + horizontalOffset,
                       NSMinY(visibleFrame) + verticalOffset);
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

    self.petWindows[profile.identifier] = window;
    self.petScales[profile.identifier] = @(window.petScale);
    self.petFacingDirections[profile.identifier] = @(window.facingRight);
    self.petClickThrough[profile.identifier] = @(window.isClickThroughEnabled);
    [self runtimeControllerForProfile:profile];
    return YES;
}

- (void)unloadPetProfileIfNeeded:(PETPetProfile *)profile {
    [self persistRuntimeSnapshotForProfile:profile];

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
        _hiddenProfileIdentifiers = [NSMutableSet set];
        _lastCognitionTimestamps = [NSMutableDictionary dictionary];
        _ocrService = [[PETOCRService alloc] init];
        NSURL *baseURL = [NSURL URLWithString:configuration.aiBaseURLString ?: @"https://api.openai.com/v1"];
        PETAIService *aiService = [[PETAIService alloc] initWithBaseURL:baseURL ?: [NSURL URLWithString:@"https://api.openai.com/v1"]];
        _cognitionEngine = [[PETStructuredCognitionEngine alloc] initWithAIService:aiService];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePetWindowRuntimeEvent:)
                                                     name:PETPetWindowDidEmitRuntimeEventNotification
                                                   object:nil];
        [self updateOCRMonitoringState];
        [self updateCognitionMonitoringState];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.ocrPollingTimer invalidate];
    [self.cognitionPollingTimer invalidate];
}

- (NSArray<PETPetProfile *> *)activeProfiles {
    return self.mutableProfiles.copy;
}

- (BOOL)addPetProfile:(PETPetProfile *)profile error:(NSError **)error {
    PETPetProfile *existingProfile = [self profileMatchingSourceURL:profile.sourceURL];
    if (existingProfile != nil) {
        [self removePetProfile:existingProfile];
    }

    if (self.mutableProfiles.count >= self.configuration.maxConcurrentPets) {
        PETPetProfile *hiddenProfile = [self firstHiddenProfile];
        if (hiddenProfile != nil) {
            [self removePetProfile:hiddenProfile];
        }
    }

    if (self.mutableProfiles.count >= self.configuration.maxConcurrentPets) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"PETPetManager"
                                         code:4001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Maximum concurrent pet count reached. Remove a visible pet or hide one before importing another."}];
        }
        return NO;
    }

    [self.mutableProfiles addObject:profile];
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
    [self notifyDidChange];
    return YES;
}

- (BOOL)isPetVisible:(PETPetProfile *)profile {
    return ![self.hiddenProfileIdentifiers containsObject:profile.identifier];
}

- (void)setVisibility:(BOOL)isVisible forPetProfile:(PETPetProfile *)profile {
    if (isVisible) {
        [self.hiddenProfileIdentifiers removeObject:profile.identifier];
        if ([self realizePetProfileIfNeeded:profile]) {
            [self.petWindows[profile.identifier] orderFrontRegardless];
        }
    } else {
        [self.hiddenProfileIdentifiers addObject:profile.identifier];
        [self unloadPetProfileIfNeeded:profile];
    }

    [self notifyDidChange];
}

- (CGFloat)scaleForPetProfile:(PETPetProfile *)profile {
    PETPetWindow *window = self.petWindows[profile.identifier];
    if (window != nil) {
        return window.petScale;
    }
    NSNumber *storedValue = self.petScales[profile.identifier];
    return storedValue != nil ? storedValue.doubleValue : 1.0;
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
    [window applyFacingRight:facingRight];
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
    [self unloadPetProfileIfNeeded:profile];
    [self.petScales removeObjectForKey:profile.identifier];
    [self.petFacingDirections removeObjectForKey:profile.identifier];
    [self.petClickThrough removeObjectForKey:profile.identifier];
    [self.characterSnapshots removeObjectForKey:profile.identifier];
    [self.hiddenProfileIdentifiers removeObject:profile.identifier];
    [self.mutableProfiles removeObject:profile];
    [self notifyDidChange];
}

- (void)setAllPetsHidden:(BOOL)hidden {
    for (PETPetProfile *profile in self.mutableProfiles) {
        [self setVisibility:!hidden forPetProfile:profile];
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
    [self.hiddenProfileIdentifiers removeAllObjects];
    [self notifyDidChange];
}

- (NSArray<NSDictionary<NSString *, id> *> *)serializedPetRecords {
    NSMutableArray<NSDictionary<NSString *, id> *> *records = [NSMutableArray arrayWithCapacity:self.mutableProfiles.count];
    for (PETPetProfile *profile in self.mutableProfiles) {
        NSString *sourcePath = profile.sourceURL.path;
        if (sourcePath.length == 0) {
            continue;
        }

        NSDictionary<NSString *, id> *record = @{
            @"sourcePath": sourcePath,
            @"displayName": profile.displayName ?: @"Pet",
            @"scale": @([self scaleForPetProfile:profile]),
            @"facingRight": @([self isFacingRightForPetProfile:profile]),
            @"clickThrough": @([self isClickThroughEnabledForPetProfile:profile]),
            @"visible": @([self isPetVisible:profile]),
            @"interactionAliases": profile.interactionAliases ?: @{},
            @"characterSnapshot": [self characterSnapshotForPetProfile:profile] ?: @{}
        };
        [records addObject:record];
    }
    return records.copy;
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

- (void)notifyDidChange {
    [self updateOCRMonitoringState];
    [self updateCognitionMonitoringState];
    [[NSNotificationCenter defaultCenter] postNotificationName:PETPetManagerDidChangePetsNotification object:self];
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
