#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETAIService : NSObject

@property (nonatomic, copy) NSURL *baseURL;

- (instancetype)initWithBaseURL:(NSURL *)baseURL;
- (void)sendInteraction:(NSString *)interaction completion:(void (^)(NSString *_Nullable reply, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
