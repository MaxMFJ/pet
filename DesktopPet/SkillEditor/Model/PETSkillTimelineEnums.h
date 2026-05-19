#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, PETSkillTimelineTrackType) {
    PETSkillTimelineTrackTypeCharacter = 0,
    PETSkillTimelineTrackTypeFX,
    PETSkillTimelineTrackTypeHitbox,
    PETSkillTimelineTrackTypeShader,
    PETSkillTimelineTrackTypeEvent,
};

typedef NS_ENUM(NSInteger, PETSkillTimelineClipKind) {
    PETSkillTimelineClipKindSpan = 0,
    PETSkillTimelineClipKindInstant,
};

typedef NS_ENUM(NSInteger, PETHitboxShape) {
    PETHitboxShapeRect = 0,
    PETHitboxShapeCircle,
    PETHitboxShapeCapsule,
};

FOUNDATION_EXPORT NSString * const PETSkillTimelineTrackTypeCharacterName;
FOUNDATION_EXPORT NSString * const PETSkillTimelineTrackTypeFXName;
FOUNDATION_EXPORT NSString * const PETSkillTimelineTrackTypeHitboxName;
FOUNDATION_EXPORT NSString * const PETSkillTimelineTrackTypeShaderName;
FOUNDATION_EXPORT NSString * const PETSkillTimelineTrackTypeEventName;

FOUNDATION_EXPORT PETSkillTimelineTrackType PETSkillTimelineTrackTypeFromString(NSString *typeName);
FOUNDATION_EXPORT NSString *PETSkillTimelineStringFromTrackType(PETSkillTimelineTrackType trackType);
