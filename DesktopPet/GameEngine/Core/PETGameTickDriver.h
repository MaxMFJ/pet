#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PETGameTickDriver;

@protocol PETGameTickDriverDelegate <NSObject>

- (void)gameTickDriver:(PETGameTickDriver *)driver didTickWithDeltaTime:(NSTimeInterval)deltaTime;

@end

@interface PETGameTickDriver : NSObject

@property (nonatomic, weak, nullable) id<PETGameTickDriverDelegate> delegate;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;
@property (nonatomic, assign) NSTimeInterval preferredFrameInterval;
@property (nonatomic, assign) NSTimeInterval maximumDeltaTime;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
