#import "PETSkillTimelineEnums.h"

NSString * const PETSkillTimelineTrackTypeCharacterName = @"character";
NSString * const PETSkillTimelineTrackTypeFXName = @"fx";
NSString * const PETSkillTimelineTrackTypeHitboxName = @"hitbox";
NSString * const PETSkillTimelineTrackTypeShaderName = @"shader";
NSString * const PETSkillTimelineTrackTypeEventName = @"event";

PETSkillTimelineTrackType PETSkillTimelineTrackTypeFromString(NSString *typeName) {
    if ([typeName isEqualToString:PETSkillTimelineTrackTypeFXName]) {
        return PETSkillTimelineTrackTypeFX;
    }
    if ([typeName isEqualToString:PETSkillTimelineTrackTypeHitboxName]) {
        return PETSkillTimelineTrackTypeHitbox;
    }
    if ([typeName isEqualToString:PETSkillTimelineTrackTypeShaderName]) {
        return PETSkillTimelineTrackTypeShader;
    }
    if ([typeName isEqualToString:PETSkillTimelineTrackTypeEventName]) {
        return PETSkillTimelineTrackTypeEvent;
    }
    return PETSkillTimelineTrackTypeCharacter;
}

NSString *PETSkillTimelineStringFromTrackType(PETSkillTimelineTrackType trackType) {
    switch (trackType) {
        case PETSkillTimelineTrackTypeFX:
            return PETSkillTimelineTrackTypeFXName;
        case PETSkillTimelineTrackTypeHitbox:
            return PETSkillTimelineTrackTypeHitboxName;
        case PETSkillTimelineTrackTypeShader:
            return PETSkillTimelineTrackTypeShaderName;
        case PETSkillTimelineTrackTypeEvent:
            return PETSkillTimelineTrackTypeEventName;
        case PETSkillTimelineTrackTypeCharacter:
        default:
            return PETSkillTimelineTrackTypeCharacterName;
    }
}
