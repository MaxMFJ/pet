#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETFXSequence : NSObject

@property (nonatomic, copy, readonly) NSString *assetName;
@property (nonatomic, copy, readonly) NSArray<NSImage *> *frames;
@property (nonatomic, assign, readonly) CGFloat framesPerSecond;

- (nullable NSImage *)frameAtIndex:(NSUInteger)index;

@end

@interface PETFXAssetCatalog : NSObject

+ (instancetype)sharedCatalog;

- (NSArray<NSString *> *)availableAssetNames;
- (nullable PETFXSequence *)sequenceNamed:(NSString *)assetName;
- (NSURL *)fxRootDirectory;
- (BOOL)importPNGSequenceFromDirectory:(NSURL *)sourceDirectory
                            assetName:(NSString *)assetName
                                error:(NSError * _Nullable * _Nullable)error;
- (void)invalidateCache;

@end

NS_ASSUME_NONNULL_END
