#import <Foundation/Foundation.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETAnimationExporter : NSObject

- (BOOL)exportPNGSequenceForProfile:(PETPetProfile *)profile
                              state:(NSString *)state
                       directoryURL:(NSURL *)directoryURL
                              scale:(CGFloat)scale
                              error:(NSError **)error;

- (BOOL)exportGIFForProfile:(PETPetProfile *)profile
                      state:(NSString *)state
                    fileURL:(NSURL *)fileURL
                      scale:(CGFloat)scale
                  loopCount:(NSInteger)loopCount
                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
