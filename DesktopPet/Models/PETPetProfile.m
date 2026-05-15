#import "PETPetProfile.h"

#import "PETAnimationFrame.h"

@implementation PETPetProfile

- (instancetype)initWithDisplayName:(NSString *)displayName
                          sourceURL:(NSURL *)sourceURL
                             frames:(NSArray<PETAnimationFrame *> *)frames
                         canvasSize:(PETPlatformSize)canvasSize {
    NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *clips = @{@"idle": frames ?: @[]};
    return [self initWithDisplayName:displayName
                           sourceURL:sourceURL
                      animationClips:clips
                        defaultState:@"idle"
                          canvasSize:canvasSize
                 usesCodexSpriteAtlas:NO
                             metadata:nil
          supportsFrameAccuratePreview:YES];
}

- (instancetype)initWithDisplayName:(NSString *)displayName
                          sourceURL:(NSURL *)sourceURL
                     animationClips:(NSDictionary<NSString *,NSArray<PETAnimationFrame *> *> *)animationClips
                       defaultState:(NSString *)defaultState
                         canvasSize:(PETPlatformSize)canvasSize
                usesCodexSpriteAtlas:(BOOL)usesCodexSpriteAtlas {
    return [self initWithDisplayName:displayName
                           sourceURL:sourceURL
                      animationClips:animationClips
                        defaultState:defaultState
                          canvasSize:canvasSize
                 usesCodexSpriteAtlas:usesCodexSpriteAtlas
                             metadata:nil
          supportsFrameAccuratePreview:YES];
}

- (instancetype)initWithDisplayName:(NSString *)displayName
                          sourceURL:(NSURL *)sourceURL
                     animationClips:(NSDictionary<NSString *,NSArray<PETAnimationFrame *> *> *)animationClips
                       defaultState:(NSString *)defaultState
                         canvasSize:(PETPlatformSize)canvasSize
                usesCodexSpriteAtlas:(BOOL)usesCodexSpriteAtlas
                            metadata:(NSDictionary<NSString *,id> *)metadata
         supportsFrameAccuratePreview:(BOOL)supportsFrameAccuratePreview {
    self = [super init];
    if (self) {
        _identifier = NSUUID.UUID.UUIDString;
        _displayName = [displayName copy];
        _sourceURL = [sourceURL copy];
        _animationClips = [animationClips copy];
        _defaultState = [defaultState copy];
        _supportedStates = [[animationClips allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        _frames = [_animationClips[_defaultState] copy] ?: @[];
        _canvasSize = canvasSize;
        _usesCodexSpriteAtlas = usesCodexSpriteAtlas;
        _metadata = [metadata copy] ?: @{};
        _supportsFrameAccuratePreview = supportsFrameAccuratePreview;
    }
    return self;
}

- (NSDictionary<NSString *,NSString *> *)interactionAliases {
    NSDictionary<NSString *, NSString *> *aliases = [self.metadata[@"interactionAliases"] isKindOfClass:NSDictionary.class] ? self.metadata[@"interactionAliases"] : nil;
    return aliases ?: @{};
}

- (NSDictionary<NSString *, NSString *> *)baseInteractionAliases {
    NSDictionary<NSString *, NSString *> *aliases = [self.metadata[@"baseInteractionAliases"] isKindOfClass:NSDictionary.class] ? self.metadata[@"baseInteractionAliases"] : nil;
    return aliases ?: @{};
}

- (NSArray<PETAnimationFrame *> *)framesForState:(NSString *)state {
    NSArray<PETAnimationFrame *> *frames = self.animationClips[state];
    if (frames.count > 0) {
        return frames;
    }
    return self.frames;
}

- (BOOL)usesSpineRuntime {
    NSString *sourceType = [self.metadata[@"sourceType"] isKindOfClass:NSString.class] ? self.metadata[@"sourceType"] : @"";
    return [sourceType isEqualToString:@"spine-runtime-json"];
}

- (BOOL)supportsDesktopPetBehavior {
    if (self.usesCodexSpriteAtlas) {
        return YES;
    }
    return [self resolvedAnimationStateForBehaviorState:@"idle"].length > 0;
}

- (NSString *)resolvedAnimationStateForBehaviorState:(NSString *)state {
    if (state.length == 0) {
        return nil;
    }

    NSDictionary<NSString *, NSString *> *stateAliases = [self.metadata[@"stateAliases"] isKindOfClass:NSDictionary.class] ? self.metadata[@"stateAliases"] : nil;
    NSString *alias = [stateAliases[state] isKindOfClass:NSString.class] ? stateAliases[state] : nil;
    if (alias.length > 0 && [self.supportedStates containsObject:alias]) {
        return alias;
    }

    if ([self.supportedStates containsObject:state]) {
        return state;
    }

    return nil;
}

- (NSString *)resolvedInteractionAnimationStateForActionKey:(NSString *)actionKey {
    if (actionKey.length == 0) {
        return nil;
    }

    return [self userInteractionAnimationStateForActionKey:actionKey] ?: [self baseInteractionAnimationStateForActionKey:actionKey];
}

- (NSString *)userInteractionAnimationStateForActionKey:(NSString *)actionKey {
    if (actionKey.length == 0) {
        return nil;
    }

    NSString *userAlias = [self.interactionAliases[actionKey] isKindOfClass:NSString.class] ? self.interactionAliases[actionKey] : nil;
    if (userAlias.length > 0 && [self.supportedStates containsObject:userAlias]) {
        return userAlias;
    }
    return nil;
}

- (NSString *)baseInteractionAnimationStateForActionKey:(NSString *)actionKey {
    if (actionKey.length == 0) {
        return nil;
    }

    NSString *baseAlias = [self.baseInteractionAliases[actionKey] isKindOfClass:NSString.class] ? self.baseInteractionAliases[actionKey] : nil;
    if (baseAlias.length > 0 && [self.supportedStates containsObject:baseAlias]) {
        return baseAlias;
    }
    return nil;
}

- (void)setInteractionAlias:(NSString *)animationState forActionKey:(NSString *)actionKey {
    if (actionKey.length == 0) {
        return;
    }

    NSMutableDictionary<NSString *, id> *metadata = [self.metadata mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *aliases = [[self interactionAliases] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (animationState.length > 0) {
        aliases[actionKey] = animationState;
    } else {
        [aliases removeObjectForKey:actionKey];
    }
    metadata[@"interactionAliases"] = aliases.copy;
    _metadata = metadata.copy;
}

- (void)setDefaultAnimationState:(NSString *)defaultState {
    if (defaultState.length == 0 || ![self.supportedStates containsObject:defaultState]) {
        return;
    }

    _defaultState = [defaultState copy];
    _frames = [self.animationClips[_defaultState] copy] ?: @[];
}

@end
