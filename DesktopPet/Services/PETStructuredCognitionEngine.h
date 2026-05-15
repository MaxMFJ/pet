#import <Foundation/Foundation.h>

@class PETAIService;
@class PETCharacterSnapshot;
@class PETStructuredCognitionSuggestion;

NS_ASSUME_NONNULL_BEGIN

@interface PETStructuredCognitionEngine : NSObject

- (instancetype)initWithAIService:(PETAIService *)aiService;
- (void)requestSuggestionForSnapshot:(PETCharacterSnapshot *)snapshot
                          completion:(void (^)(PETStructuredCognitionSuggestion *_Nullable suggestion, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
