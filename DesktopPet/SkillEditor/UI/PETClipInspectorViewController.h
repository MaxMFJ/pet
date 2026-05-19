#import <Cocoa/Cocoa.h>

@class PETSkillTimelineClip;
@class PETSkillTimelineDocument;
@class PETSpineMetalView;

NS_ASSUME_NONNULL_BEGIN

@protocol PETClipInspectorDelegate <NSObject>
- (void)clipInspectorDidUpdateClip:(PETSkillTimelineClip *)clip;
- (void)clipInspectorDidChangeClipTiming:(PETSkillTimelineClip *)clip;
@end

@interface PETClipInspectorViewController : NSViewController

@property (nonatomic, weak, nullable) id<PETClipInspectorDelegate> inspectorDelegate;
@property (nonatomic, strong, nullable) PETSkillTimelineDocument *document;

- (void)displayClip:(nullable PETSkillTimelineClip *)clip;
- (void)reloadBoneAndAssetChoices;
- (void)setSpineViewForBoneChoices:(PETSpineMetalView *)spineView profileId:(NSString *)profileId;

@end

NS_ASSUME_NONNULL_END
