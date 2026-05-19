#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class PETSkillTimelineClip;

NS_ASSUME_NONNULL_BEGIN

@interface PETFXPreviewInstance : NSObject

@property (nonatomic, strong) PETSkillTimelineClip *clip;
@property (nonatomic, copy) NSDictionary<NSString *, id> *payload;
@property (nonatomic, assign) NSTimeInterval clipLocalTime;
@property (nonatomic, strong, nullable) NSImage *currentFrame;
@property (nonatomic, assign) BOOL usesPlaceholder;

+ (instancetype)instanceWithClip:(PETSkillTimelineClip *)clip clipLocalTime:(NSTimeInterval)clipLocalTime;

@end

NS_ASSUME_NONNULL_END
