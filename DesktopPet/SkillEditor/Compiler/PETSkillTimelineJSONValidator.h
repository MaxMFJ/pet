#import <Foundation/Foundation.h>

@class PETSkillTimelineDocument;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillTimelineJSONValidator : NSObject

+ (BOOL)validateDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)validateDocument:(PETSkillTimelineDocument *)document error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
