#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETShaderOverlayView : NSView

@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *activeShaders;

@end

NS_ASSUME_NONNULL_END
