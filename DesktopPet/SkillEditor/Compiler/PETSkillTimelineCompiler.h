#import <Foundation/Foundation.h>

@class PETSkillTimelineDocument;
@class PETSkillDefinition;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillTimelineCompiler : NSObject

+ (NSDictionary<NSString *, id> *)compileToSkillDictionary:(PETSkillTimelineDocument *)document;
+ (nullable PETSkillDefinition *)compileToSkillDefinition:(PETSkillTimelineDocument *)document;

@end

NS_ASSUME_NONNULL_END
