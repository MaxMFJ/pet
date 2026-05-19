#import "PETGameTickDriver.h"

@interface PETGameTickDriver ()

@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSDate *lastTickDate;
@property (nonatomic, assign, getter=isRunning) BOOL running;

@end

@implementation PETGameTickDriver

- (instancetype)init {
    self = [super init];
    if (self) {
        _preferredFrameInterval = 1.0 / 60.0;
        _maximumDeltaTime = 1.0 / 20.0;
    }
    return self;
}

- (void)start {
    if (self.isRunning) {
        return;
    }
    self.running = YES;
    self.lastTickDate = NSDate.date;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.preferredFrameInterval
                                                  target:self
                                                selector:@selector(handleTimer:)
                                                userInfo:nil
                                                 repeats:YES];
    self.timer.tolerance = self.preferredFrameInterval * 0.25;
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    self.lastTickDate = nil;
    self.running = NO;
}

- (void)handleTimer:(NSTimer *)timer {
    (void)timer;
    NSDate *now = NSDate.date;
    NSTimeInterval deltaTime = self.lastTickDate != nil ? [now timeIntervalSinceDate:self.lastTickDate] : self.preferredFrameInterval;
    self.lastTickDate = now;
    deltaTime = MIN(MAX(deltaTime, 0.0), self.maximumDeltaTime);
    [self.delegate gameTickDriver:self didTickWithDeltaTime:deltaTime];
}

@end
