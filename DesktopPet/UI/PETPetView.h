#import <Cocoa/Cocoa.h>

@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETPetView : NSView

@property (nonatomic, copy, nullable) void (^dragStateChangeHandler)(BOOL isDragging);
@property (nonatomic, copy, nullable) void (^dragMovementHandler)(CGFloat deltaX);
@property (nonatomic, copy, nullable) void (^interactionHandler)(void);
@property (nonatomic, copy, nullable) void (^secondaryInteractionHandler)(void);
@property (nonatomic, copy, nullable) void (^menuActionHandler)(NSString *state);
@property (nonatomic, copy, readonly) NSString *currentState;
@property (nonatomic, assign) BOOL facingRight;

- (instancetype)initWithProfile:(PETPetProfile *)profile;
- (void)startAnimating;
- (void)playState:(NSString *)state;
- (void)pauseAnimation;
- (void)resumeDefaultAnimation;
- (BOOL)containsInteractiveContentAtPoint:(NSPoint)point;
- (BOOL)containsDraggableContentAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
