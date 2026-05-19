#import <Cocoa/Cocoa.h>

@class PETPetManager;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillEditorViewController : NSViewController

- (instancetype)initWithPetManager:(PETPetManager *)petManager;

@end

NS_ASSUME_NONNULL_END
