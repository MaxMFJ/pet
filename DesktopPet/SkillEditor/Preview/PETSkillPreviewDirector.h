#import <Foundation/Foundation.h>

@class PETSkillTimelineDocument;
@class PETSpineMetalView;
@class PETHitboxOverlayView;
@class PETFXOverlayView;
@class PETShaderOverlayView;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillPreviewDirector : NSObject

@property (nonatomic, strong) PETSkillTimelineDocument *document;
@property (nonatomic, weak, nullable) PETSpineMetalView *spineView;
@property (nonatomic, weak, nullable) PETHitboxOverlayView *hitboxOverlay;
@property (nonatomic, weak, nullable) PETFXOverlayView *fxOverlay;
@property (nonatomic, weak, nullable) PETShaderOverlayView *shaderOverlay;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign) BOOL facingRight;

- (void)start;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time;
- (void)stepFrame:(NSInteger)direction;
- (void)syncPreviewToPlayhead;

@end

NS_ASSUME_NONNULL_END
