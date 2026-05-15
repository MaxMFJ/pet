#import <Cocoa/Cocoa.h>

@class PETPetManager;

NS_ASSUME_NONNULL_BEGIN

@interface PETAssetImportManager : NSObject

- (instancetype)initWithPetManager:(PETPetManager *)petManager;
- (void)importPetFromOpenPanel:(id _Nullable)sender;
- (BOOL)importPetAtURL:(NSURL *)fileURL error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
