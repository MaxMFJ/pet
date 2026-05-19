#import <Cocoa/Cocoa.h>

@class PETSkillTimelineDocument;
@class PETSkillTimelineClip;

NS_ASSUME_NONNULL_BEGIN

@protocol PETTimelineViewDelegate <NSObject>
- (void)timelineViewDidChangePlayhead:(NSTimeInterval)time;
- (void)timelineViewDidSelectClip:(nullable PETSkillTimelineClip *)clip;
- (void)timelineViewDidUpdateClip:(PETSkillTimelineClip *)clip;
- (void)timelineViewDidDeleteClip:(PETSkillTimelineClip *)clip;
@optional
- (void)timelineViewWillBeginEditingClip:(PETSkillTimelineClip *)clip;
- (void)timelineViewDidRequestCopyClip:(PETSkillTimelineClip *)clip;
- (void)timelineViewDidRequestPasteClip;
@end

@interface PETTimelineView : NSView

@property (nonatomic, strong) PETSkillTimelineDocument *document;
@property (nonatomic, weak, nullable) id<PETTimelineViewDelegate> delegate;
@property (nonatomic, strong, nullable) PETSkillTimelineClip *selectedClip;

- (void)reloadData;
- (BOOL)becomeFirstResponder;

@end

NS_ASSUME_NONNULL_END
