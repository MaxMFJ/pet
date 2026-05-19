#import "PETSkillTimelineJSONValidator.h"

#import "../Model/PETSkillTimelineDocument.h"
#import "../Model/PETSkillTimelineEnums.h"
#import "PETSkillTimelineJSONSerializer.h"

static NSString * const PETSkillTimelineValidationErrorDomain = @"PETSkillTimelineJSONValidator";

@implementation PETSkillTimelineJSONValidator

+ (BOOL)validateDocument:(PETSkillTimelineDocument *)document error:(NSError * _Nullable __autoreleasing *)error {
    return [self validateDictionary:[PETSkillTimelineJSONSerializer dictionaryFromDocument:document] error:error];
}

+ (BOOL)validateDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError * _Nullable __autoreleasing *)error {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return [self failWithMessage:@"Root value must be a JSON object." error:error];
    }

    NSInteger formatVersion = [dictionary[@"formatVersion"] integerValue];
    if (formatVersion != 1) {
        return [self failWithMessage:@"formatVersion must be 1." error:error];
    }

    NSString *skillId = [dictionary[@"skillId"] isKindOfClass:NSString.class] ? dictionary[@"skillId"] : @"";
    if (skillId.length == 0) {
        return [self failWithMessage:@"skillId is required." error:error];
    }

    NSTimeInterval duration = [dictionary[@"duration"] doubleValue];
    if (duration < 0.01) {
        return [self failWithMessage:@"duration must be at least 0.01 seconds." error:error];
    }

    NSString *animation = [dictionary[@"characterAnimation"] isKindOfClass:NSString.class] ? dictionary[@"characterAnimation"] : @"";
    if (animation.length == 0) {
        return [self failWithMessage:@"characterAnimation is required." error:error];
    }

    NSArray *tracks = [dictionary[@"tracks"] isKindOfClass:NSArray.class] ? dictionary[@"tracks"] : nil;
    if (tracks == nil) {
        return [self failWithMessage:@"tracks array is required." error:error];
    }

    NSSet<NSString *> *allowedTypes = [NSSet setWithArray:@[
        PETSkillTimelineTrackTypeCharacterName,
        PETSkillTimelineTrackTypeFXName,
        PETSkillTimelineTrackTypeHitboxName,
        PETSkillTimelineTrackTypeShaderName,
        PETSkillTimelineTrackTypeEventName
    ]];

    for (id trackObject in tracks) {
        if (![trackObject isKindOfClass:NSDictionary.class]) {
            return [self failWithMessage:@"Each track must be an object." error:error];
        }
        NSDictionary *track = (NSDictionary *)trackObject;
        NSString *typeName = [track[@"type"] isKindOfClass:NSString.class] ? track[@"type"] : @"";
        if (![allowedTypes containsObject:typeName]) {
            return [self failWithMessage:[NSString stringWithFormat:@"Unknown track type '%@'.", typeName] error:error];
        }

        NSArray *clips = [track[@"clips"] isKindOfClass:NSArray.class] ? track[@"clips"] : nil;
        if (clips == nil) {
            return [self failWithMessage:@"Track clips must be an array." error:error];
        }

        for (id clipObject in clips) {
            if (![clipObject isKindOfClass:NSDictionary.class]) {
                return [self failWithMessage:@"Each clip must be an object." error:error];
            }
            NSDictionary *clip = (NSDictionary *)clipObject;
            NSString *clipId = [clip[@"clipId"] isKindOfClass:NSString.class] ? clip[@"clipId"] : @"";
            if (clipId.length == 0) {
                return [self failWithMessage:@"clipId is required on every clip." error:error];
            }
            if (clip[@"start"] == nil) {
                return [self failWithMessage:[NSString stringWithFormat:@"Clip '%@' is missing start.", clipId] error:error];
            }
            NSTimeInterval start = [clip[@"start"] doubleValue];
            if (start < 0.0 || start > duration) {
                return [self failWithMessage:[NSString stringWithFormat:@"Clip '%@' start is outside duration.", clipId] error:error];
            }
            if (clip[@"end"] != nil) {
                NSTimeInterval end = [clip[@"end"] doubleValue];
                if (end < start) {
                    return [self failWithMessage:[NSString stringWithFormat:@"Clip '%@' end must be >= start.", clipId] error:error];
                }
            }
        }
    }

    return YES;
}

+ (BOOL)failWithMessage:(NSString *)message error:(NSError * _Nullable __autoreleasing *)error {
    if (error != NULL) {
        *error = [NSError errorWithDomain:PETSkillTimelineValidationErrorDomain
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

@end
