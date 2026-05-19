#import <Cocoa/Cocoa.h>

@class PETSpineMetalView;

NS_ASSUME_NONNULL_BEGIN

@interface PETHitboxOverlayView : NSView

@property (nonatomic, weak, nullable) PETSpineMetalView *spineView;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *activeHitboxes;
@property (nonatomic, assign) BOOL facingRight;
@property (nonatomic, copy, nullable) void (^onPayloadDragged)(NSDictionary<NSString *, id> *payload);

@end

NS_ASSUME_NONNULL_END
