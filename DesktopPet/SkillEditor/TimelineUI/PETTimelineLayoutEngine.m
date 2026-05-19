#import "PETTimelineLayoutEngine.h"

#import "../Model/PETSkillTimelineClip.h"

@implementation PETTimelineLayoutMetrics

+ (instancetype)defaultMetrics {
    PETTimelineLayoutMetrics *metrics = [[PETTimelineLayoutMetrics alloc] init];
    metrics.pixelsPerSecond = 120.0;
    metrics.trackHeight = 28.0;
    metrics.rulerHeight = 24.0;
    metrics.snapInterval = 1.0 / 60.0;
    return metrics;
}

@end

@implementation PETTimelineLayoutEngine

- (CGFloat)xForTime:(NSTimeInterval)time metrics:(PETTimelineLayoutMetrics *)metrics {
    return (CGFloat)time * metrics.pixelsPerSecond;
}

- (NSTimeInterval)timeForX:(CGFloat)x metrics:(PETTimelineLayoutMetrics *)metrics {
    if (metrics.pixelsPerSecond <= 0.0) {
        return 0.0;
    }
    return MAX(0.0, x / metrics.pixelsPerSecond);
}

- (NSTimeInterval)snapTime:(NSTimeInterval)time metrics:(PETTimelineLayoutMetrics *)metrics {
    if (metrics.snapInterval <= 0.0) {
        return time;
    }
    return round(time / metrics.snapInterval) * metrics.snapInterval;
}

- (CGRect)frameForClip:(PETSkillTimelineClip *)clip
               rowIndex:(NSInteger)rowIndex
                metrics:(PETTimelineLayoutMetrics *)metrics
             contentWidth:(CGFloat)contentWidth
          contentHeight:(CGFloat)contentHeight {
    (void)contentWidth;
    CGFloat y = contentHeight - metrics.rulerHeight - ((rowIndex + 1) * metrics.trackHeight);
    CGFloat startX = [self xForTime:clip.startTime metrics:metrics];
    CGFloat endX = [self xForTime:MAX(clip.endTime, clip.startTime + (1.0 / 60.0)) metrics:metrics];
    return CGRectMake(startX, y + 3.0, MAX(6.0, endX - startX), metrics.trackHeight - 6.0);
}

@end
