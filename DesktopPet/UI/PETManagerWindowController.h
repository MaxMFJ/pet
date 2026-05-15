#import <Cocoa/Cocoa.h>

@class PETAppConfig;
@class PETAssetImportManager;
@class PETPetManager;

NS_ASSUME_NONNULL_BEGIN

@interface PETManagerWindowController : NSWindowController

- (instancetype)initWithPetManager:(PETPetManager *)petManager
                     configuration:(PETAppConfig *)configuration
                assetImportManager:(PETAssetImportManager *)assetImportManager;

@end

NS_ASSUME_NONNULL_END
