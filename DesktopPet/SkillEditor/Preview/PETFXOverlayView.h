#import <Cocoa/Cocoa.h>

@class PETSpineMetalView;
@class PETFXPreviewInstance;

NS_ASSUME_NONNULL_BEGIN

@interface PETFXOverlayView : NSView

@property (nonatomic, weak, nullable) PETSpineMetalView *spineView;
@property (nonatomic, copy) NSArray<PETFXPreviewInstance *> *activeInstances;
@property (nonatomic, assign) BOOL facingRight;
@property (nonatomic, copy, nullable) void (^onPayloadDragged)(NSDictionary<NSString *, id> *payload, PETFXPreviewInstance *instance);

@end

NS_ASSUME_NONNULL_END
