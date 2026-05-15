#import <Foundation/Foundation.h>

@class PETCharacterEmotion;
@class PETCharacterIntent;
@class PETCharacterSnapshot;

NS_ASSUME_NONNULL_BEGIN

@interface PETEmotionEngine : NSObject

- (PETCharacterEmotion *)emotionForIntent:(PETCharacterIntent *)intent
                         previousSnapshot:(nullable PETCharacterSnapshot *)previousSnapshot;

@end

NS_ASSUME_NONNULL_END
