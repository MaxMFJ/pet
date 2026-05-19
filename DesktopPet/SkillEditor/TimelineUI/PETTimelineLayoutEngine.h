#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class PETSkillTimelineClip;
@class PETSkillTimelineTrack;

NS_ASSUME_NONNULL_BEGIN

@interface PETTimelineLayoutMetrics : NSObject

@property (nonatomic, assign) CGFloat pixelsPerSecond;
@property (nonatomic, assign) CGFloat trackHeight;
@property (nonatomic, assign) CGFloat rulerHeight;
@property (nonatomic, assign) NSTimeInterval snapInterval;

+ (instancetype)defaultMetrics;

@end

@interface PETTimelineLayoutEngine : NSObject

- (CGFloat)xForTime:(NSTimeInterval)time metrics:(PETTimelineLayoutMetrics *)metrics;
- (NSTimeInterval)timeForX:(CGFloat)x metrics:(PETTimelineLayoutMetrics *)metrics;
- (NSTimeInterval)snapTime:(NSTimeInterval)time metrics:(PETTimelineLayoutMetrics *)metrics;
- (CGRect)frameForClip:(PETSkillTimelineClip *)clip
               rowIndex:(NSInteger)rowIndex
                metrics:(PETTimelineLayoutMetrics *)metrics
             contentWidth:(CGFloat)contentWidth
          contentHeight:(CGFloat)contentHeight;

@end

NS_ASSUME_NONNULL_END
