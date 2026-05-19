#import "PETSkillTimelineCompiler.h"

#import "../../GameEngine/Skill/PETSkillDefinition.h"
#import "../Model/PETSkillTimelineDocument.h"
#import "../Model/PETSkillTimelineEnums.h"

@implementation PETSkillTimelineCompiler

+ (NSDictionary<NSString *,id> *)compileToSkillDictionary:(PETSkillTimelineDocument *)document {
    NSMutableArray *hitWindows = [NSMutableArray array];
    NSMutableArray *effects = [NSMutableArray array];

    for (PETSkillTimelineTrack *track in document.tracks) {
        if (track.trackType == PETSkillTimelineTrackTypeHitbox) {
            for (PETSkillTimelineClip *clip in track.clips) {
                NSDictionary *payload = clip.payload ?: @{};
                [hitWindows addObject:@{
                    @"windowId": payload[@"windowId"] ?: clip.clipIdentifier,
                    @"startTime": @(clip.startTime),
                    @"endTime": @(clip.endTime),
                    @"collisionMode": payload[@"collisionMode"] ?: @"pixelOverlap",
                    @"reactionId": payload[@"reactionId"] ?: @"hit_stun_light",
                    @"targetFilter": @"enemy",
                    @"shape": payload[@"shape"] ?: @"rect",
                    @"socket": payload[@"socket"] ?: @"",
                    @"x": payload[@"x"] ?: @0,
                    @"y": payload[@"y"] ?: @0,
                    @"width": payload[@"width"] ?: @0,
                    @"height": payload[@"height"] ?: @0,
                    @"damage": payload[@"damage"] ?: @0
                }];
            }
        } else if (track.trackType == PETSkillTimelineTrackTypeFX) {
            for (PETSkillTimelineClip *clip in track.clips) {
                [effects addObject:@{
                    @"type": @"spawnFX",
                    @"startTime": @(clip.startTime),
                    @"endTime": @(clip.endTime),
                    @"payload": clip.payload ?: @{}
                }];
            }
        } else if (track.trackType == PETSkillTimelineTrackTypeEvent) {
            for (PETSkillTimelineClip *clip in track.clips) {
                [effects addObject:@{
                    @"type": @"timelineEvent",
                    @"startTime": @(clip.startTime),
                    @"endTime": @(clip.endTime),
                    @"payload": clip.payload ?: @{}
                }];
            }
        }
    }

    return @{
        @"skillId": document.skillIdentifier ?: @"timeline_skill",
        @"displayName": document.displayName ?: document.skillIdentifier,
        @"castType": @"skill",
        @"entryPhase": @"main",
        @"phases": @[@{
            @"phaseId": @"main",
            @"startTime": @0,
            @"duration": @(document.duration),
            @"animationState": document.characterAnimation ?: @"idle",
            @"movementLock": @YES,
            @"allowMovementDuringCast": @NO,
            @"hitWindows": hitWindows,
            @"effects": effects,
            @"transitions": @[@{ @"type": @"onPhaseComplete", @"toPhase": @"end" }]
        }]
    };
}

+ (PETSkillDefinition *)compileToSkillDefinition:(PETSkillTimelineDocument *)document {
    NSDictionary *dictionary = [self compileToSkillDictionary:document];
    return [[PETSkillDefinition alloc] initWithDictionaryRepresentation:dictionary];
}

@end
