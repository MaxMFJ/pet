#import <Foundation/Foundation.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETAnimationSourceLoader : NSObject

- (PETPetProfile * _Nullable)loadAnimationSourceAtURL:(NSURL *)fileURL error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
