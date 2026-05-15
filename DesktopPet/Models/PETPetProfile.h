#import <Foundation/Foundation.h>

#import "../Config/PETPlatformCompatibility.h"

@class PETAnimationFrame;

NS_ASSUME_NONNULL_BEGIN

@interface PETPetProfile : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, readonly) NSURL *sourceURL;
@property (nonatomic, copy, readonly) NSArray<PETAnimationFrame *> *frames;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *animationClips;
@property (nonatomic, copy, readonly) NSArray<NSString *> *supportedStates;
@property (nonatomic, copy, readonly) NSString *defaultState;
@property (nonatomic, assign, readonly) PETPlatformSize canvasSize;
@property (nonatomic, assign, readonly) BOOL usesCodexSpriteAtlas;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *metadata;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *interactionAliases;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *baseInteractionAliases;
@property (nonatomic, assign, readonly) BOOL supportsFrameAccuratePreview;
@property (nonatomic, assign, readonly) BOOL usesSpineRuntime;
@property (nonatomic, assign, readonly) BOOL supportsDesktopPetBehavior;

- (instancetype)initWithDisplayName:(NSString *)displayName
                          sourceURL:(NSURL *)sourceURL
                             frames:(NSArray<PETAnimationFrame *> *)frames
                         canvasSize:(PETPlatformSize)canvasSize;

- (instancetype)initWithDisplayName:(NSString *)displayName
                          sourceURL:(NSURL *)sourceURL
                     animationClips:(NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *)animationClips
                       defaultState:(NSString *)defaultState
                         canvasSize:(PETPlatformSize)canvasSize
                usesCodexSpriteAtlas:(BOOL)usesCodexSpriteAtlas;

- (instancetype)initWithDisplayName:(NSString *)displayName
                          sourceURL:(NSURL *)sourceURL
                     animationClips:(NSDictionary<NSString *, NSArray<PETAnimationFrame *> *> *)animationClips
                       defaultState:(NSString *)defaultState
                         canvasSize:(PETPlatformSize)canvasSize
                usesCodexSpriteAtlas:(BOOL)usesCodexSpriteAtlas
                            metadata:(NSDictionary<NSString *, id> * _Nullable)metadata
         supportsFrameAccuratePreview:(BOOL)supportsFrameAccuratePreview;

- (NSArray<PETAnimationFrame *> *)framesForState:(NSString *)state;
- (nullable NSString *)resolvedAnimationStateForBehaviorState:(NSString *)state;
- (nullable NSString *)resolvedInteractionAnimationStateForActionKey:(NSString *)actionKey;
- (nullable NSString *)userInteractionAnimationStateForActionKey:(NSString *)actionKey;
- (nullable NSString *)baseInteractionAnimationStateForActionKey:(NSString *)actionKey;
- (void)setDefaultAnimationState:(NSString *)defaultState;
- (void)setInteractionAlias:(nullable NSString *)animationState forActionKey:(NSString *)actionKey;

@end

NS_ASSUME_NONNULL_END
