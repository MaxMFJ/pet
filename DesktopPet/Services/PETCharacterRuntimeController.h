#import <Foundation/Foundation.h>

@class PETCharacterSnapshot;
@class PETPetProfile;
@class PETStructuredCognitionSuggestion;

NS_ASSUME_NONNULL_BEGIN

@interface PETCharacterRuntimeController : NSObject

@property (nonatomic, strong, readonly) PETPetProfile *profile;
@property (nonatomic, strong, readonly) PETCharacterSnapshot *currentSnapshot;

- (instancetype)initWithProfile:(PETPetProfile *)profile;
- (void)restoreFromSerializedSnapshot:(NSDictionary<NSString *, id> *)snapshotDictionary;
- (void)recordActionKey:(NSString *)actionKey
  fallbackBehaviorState:(nullable NSString *)fallbackBehaviorState
   resolvedAnimationState:(NSString *)resolvedAnimationState
                  context:(nullable NSDictionary<NSString *, id> *)context;
- (void)previewAnimationState:(NSString *)animationState;
- (void)resumeAmbientBehavior;
- (void)applyStructuredCognitionSuggestion:(PETStructuredCognitionSuggestion *)suggestion;
- (NSDictionary<NSString *, id> *)serializedSnapshot;
- (NSString *)runtimeSummary;

@end

NS_ASSUME_NONNULL_END
