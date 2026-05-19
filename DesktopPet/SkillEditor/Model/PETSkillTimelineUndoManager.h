#import <Foundation/Foundation.h>

@class PETSkillTimelineDocument;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillTimelineUndoManager : NSObject

@property (nonatomic, assign, readonly) BOOL canUndo;
@property (nonatomic, assign, readonly) BOOL canRedo;

- (void)prepareWithDocument:(PETSkillTimelineDocument *)document;
- (void)recordSnapshotIfNeeded;
- (void)recordSnapshotNow;
- (BOOL)undo;
- (BOOL)redo;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
