#import "PETSkillEditorRuntimeBridge.h"

#import "../../GameEngine/Core/PETGameCommand.h"
#import "../../GameEngine/Skill/PETSkillLibrary.h"
#import "../../Managers/PETPetManager.h"
#import "../../Models/PETPetProfile.h"
#import "../Model/PETSkillTimelineDocument.h"
#import "PETSkillTimelineCompiler.h"

@implementation PETSkillEditorRuntimeBridge

+ (NSDictionary<NSString *,id> *)skillsFileDictionaryForDocument:(PETSkillTimelineDocument *)document {
    NSDictionary *skill = [PETSkillTimelineCompiler compileToSkillDictionary:document];
    return @{
        @"formatVersion": @(1),
        @"skills": @[skill]
    };
}

+ (BOOL)mergeDocumentIntoSkillLibrary:(PETSkillTimelineDocument *)document
                            petManager:(PETPetManager *)petManager
                                 error:(NSError * _Nullable __autoreleasing *)error {
    NSDictionary *root = [self skillsFileDictionaryForDocument:document];
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:error];
    if (data == nil) {
        return NO;
    }
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"timeline-preview-%@.json", document.skillIdentifier ?: @"skill"]];
    NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
    if (![data writeToURL:tempURL options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    return [petManager mergeSkillLibraryFromJSONURL:tempURL error:error];
}

+ (BOOL)previewSkillInGameForDocument:(PETSkillTimelineDocument *)document
                            petProfile:(PETPetProfile *)petProfile
                            petManager:(PETPetManager *)petManager
                                 error:(NSError * _Nullable __autoreleasing *)error {
    if (![self mergeDocumentIntoSkillLibrary:document petManager:petManager error:error]) {
        return NO;
    }
    PETGameCommand *command = [[PETGameCommand alloc] initWithPetIdentifier:petProfile.identifier
                                                                commandType:PETGameCommandSkillCast
                                                                     source:PETGameCommandSourceDebug
                                                                  direction:nil
                                                             skillIdentifier:document.skillIdentifier
                                                                   strength:1.0
                                                                    context:@{ @"actionKey": @"combat.skill.preview" }];
    [petManager submitGameCommand:command];
    return YES;
}

@end
