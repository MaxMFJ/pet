#import <Foundation/Foundation.h>

#import "../Config/PETPlatformCompatibility.h"

@class PETAnimationFrame;

NS_ASSUME_NONNULL_BEGIN

@interface PETWebPDecoder : NSObject

- (nullable NSArray<PETAnimationFrame *> *)decodeFramesAtURL:(NSURL *)fileURL
                                                  canvasSize:(PETPlatformSize *)canvasSize
                                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
