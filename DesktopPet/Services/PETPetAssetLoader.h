#import <Foundation/Foundation.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETPetAssetLoader : NSObject

- (nullable PETPetProfile *)loadPetProfileAtURL:(NSURL *)fileURL error:(NSError **)error;
- (nullable PETPetProfile *)loadPetProfileFromPackageAtURL:(NSURL *)packageURL error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
