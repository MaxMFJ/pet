#import <Foundation/Foundation.h>

@class PETSkillTimelineDocument;

NS_ASSUME_NONNULL_BEGIN

@interface PETSkillTimelineJSONSerializer : NSObject

+ (NSDictionary<NSString *, id> *)dictionaryFromDocument:(PETSkillTimelineDocument *)document;
+ (BOOL)exportDocument:(PETSkillTimelineDocument *)document
                 toURL:(NSURL *)url
                 error:(NSError * _Nullable * _Nullable)error;
+ (nullable PETSkillTimelineDocument *)documentFromDictionary:(NSDictionary<NSString *, id> *)dictionary;
+ (nullable PETSkillTimelineDocument *)documentFromURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
+ (NSURL *)defaultExportDirectory;
+ (nullable PETSkillTimelineDocument *)bundledDocumentNamed:(NSString *)skillIdentifier;

@end

NS_ASSUME_NONNULL_END
