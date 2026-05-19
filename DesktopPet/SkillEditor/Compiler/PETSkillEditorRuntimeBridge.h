#import <Foundation/Foundation.h>

@class PETSkillTimelineDocument;
@class PETPetManager;
@class PETPetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillEditorRuntimeBridge : NSObject

+ (NSDictionary<NSString *, id> *)skillsFileDictionaryForDocument:(PETSkillTimelineDocument *)document;
+ (BOOL)mergeDocumentIntoSkillLibrary:(PETSkillTimelineDocument *)document
                            petManager:(PETPetManager *)petManager
                                 error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)previewSkillInGameForDocument:(PETSkillTimelineDocument *)document
                            petProfile:(PETPetProfile *)petProfile
                            petManager:(PETPetManager *)petManager
                                 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
