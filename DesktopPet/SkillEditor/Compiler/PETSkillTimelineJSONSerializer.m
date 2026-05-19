#import "PETSkillTimelineJSONSerializer.h"

#import "../Model/PETSkillTimelineDocument.h"
#import "../Model/PETSkillTimelineEnums.h"

static NSString * const PETSkillTimelineJSONErrorDomain = @"PETSkillTimelineJSONSerializer";

@implementation PETSkillTimelineJSONSerializer

+ (NSDictionary<NSString *,id> *)dictionaryFromDocument:(PETSkillTimelineDocument *)document {
    NSMutableArray *tracks = [NSMutableArray array];
    for (PETSkillTimelineTrack *track in document.tracks) {
        NSMutableArray *clips = [NSMutableArray array];
        for (PETSkillTimelineClip *clip in track.clips) {
            NSMutableDictionary *clipDictionary = [@{
                @"clipId": clip.clipIdentifier ?: @"",
                @"start": @(clip.startTime),
                @"payload": clip.payload ?: @{}
            } mutableCopy];
            if (clip.clipKind == PETSkillTimelineClipKindSpan) {
                clipDictionary[@"end"] = @(clip.endTime);
            }
            [clips addObject:clipDictionary];
        }
        [tracks addObject:@{
            @"trackId": track.trackIdentifier ?: @"",
            @"type": PETSkillTimelineStringFromTrackType(track.trackType),
            @"displayName": track.displayName ?: @"",
            @"clips": clips
        }];
    }

    return @{
        @"formatVersion": @(document.formatVersion > 0 ? document.formatVersion : 1),
        @"skillId": document.skillIdentifier ?: @"",
        @"displayName": document.displayName ?: @"",
        @"duration": @(document.duration),
        @"characterProfileId": document.characterProfileId ?: @"",
        @"characterAnimation": document.characterAnimation ?: @"",
        @"tracks": tracks
    };
}

+ (BOOL)exportDocument:(PETSkillTimelineDocument *)document
                 toURL:(NSURL *)url
                 error:(NSError * _Nullable __autoreleasing *)error {
    NSDictionary *dictionary = [self dictionaryFromDocument:document];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:error];
    if (data == nil) {
        return NO;
    }
    NSFileManager *fileManager = NSFileManager.defaultManager;
    [fileManager createDirectoryAtURL:url.URLByDeletingLastPathComponent
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

+ (PETSkillTimelineDocument *)documentFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    PETSkillTimelineDocument *document = [PETSkillTimelineDocument emptyDocument];
    document.formatVersion = [dictionary[@"formatVersion"] integerValue];
    document.skillIdentifier = [dictionary[@"skillId"] isKindOfClass:NSString.class] ? dictionary[@"skillId"] : document.skillIdentifier;
    document.displayName = [dictionary[@"displayName"] isKindOfClass:NSString.class] ? dictionary[@"displayName"] : document.displayName;
    document.duration = MAX(0.01, [dictionary[@"duration"] doubleValue]);
    document.characterProfileId = [dictionary[@"characterProfileId"] isKindOfClass:NSString.class] ? dictionary[@"characterProfileId"] : @"";
    document.characterAnimation = [dictionary[@"characterAnimation"] isKindOfClass:NSString.class] ? dictionary[@"characterAnimation"] : @"idle";

    [document.tracks removeAllObjects];
    NSArray *tracks = [dictionary[@"tracks"] isKindOfClass:NSArray.class] ? dictionary[@"tracks"] : @[];
    for (NSDictionary *trackDictionary in tracks) {
        if (![trackDictionary isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *typeName = [trackDictionary[@"type"] isKindOfClass:NSString.class] ? trackDictionary[@"type"] : PETSkillTimelineTrackTypeCharacterName;
        PETSkillTimelineTrack *track = [[PETSkillTimelineTrack alloc] init];
        track.trackIdentifier = [trackDictionary[@"trackId"] isKindOfClass:NSString.class] ? trackDictionary[@"trackId"] : NSUUID.UUID.UUIDString;
        track.trackType = PETSkillTimelineTrackTypeFromString(typeName);
        track.displayName = [trackDictionary[@"displayName"] isKindOfClass:NSString.class] ? trackDictionary[@"displayName"] : track.trackIdentifier;

        NSArray *clips = [trackDictionary[@"clips"] isKindOfClass:NSArray.class] ? trackDictionary[@"clips"] : @[];
        for (NSDictionary *clipDictionary in clips) {
            if (![clipDictionary isKindOfClass:NSDictionary.class]) {
                continue;
            }
            PETSkillTimelineClip *clip = [[PETSkillTimelineClip alloc] init];
            clip.clipIdentifier = [clipDictionary[@"clipId"] isKindOfClass:NSString.class] ? clipDictionary[@"clipId"] : NSUUID.UUID.UUIDString;
            clip.trackType = track.trackType;
            clip.startTime = MAX(0.0, [clipDictionary[@"start"] doubleValue]);
            if (clipDictionary[@"end"] != nil) {
                clip.endTime = MAX(clip.startTime, [clipDictionary[@"end"] doubleValue]);
                clip.clipKind = PETSkillTimelineClipKindSpan;
            } else {
                clip.endTime = clip.startTime;
                clip.clipKind = PETSkillTimelineClipKindInstant;
            }
            clip.payload = [clipDictionary[@"payload"] isKindOfClass:NSDictionary.class] ? clipDictionary[@"payload"] : @{};
            [track.clips addObject:clip];
        }
        [document.tracks addObject:track];
    }

    [document ensureDefaultTracks];
    return document;
}

+ (PETSkillTimelineDocument *)documentFromURL:(NSURL *)url error:(NSError * _Nullable __autoreleasing *)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (data == nil) {
        return nil;
    }
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![jsonObject isKindOfClass:NSDictionary.class]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:PETSkillTimelineJSONErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Timeline JSON root must be an object."}];
        }
        return nil;
    }
    return [self documentFromDictionary:(NSDictionary *)jsonObject];
}

+ (PETSkillTimelineDocument *)bundledDocumentNamed:(NSString *)skillIdentifier {
    if (skillIdentifier.length == 0) {
        return nil;
    }
    NSURL *bundleURL = [NSBundle.mainBundle URLForResource:skillIdentifier
                                             withExtension:@"timeline.json"
                                              subdirectory:@"SkillTimelines"];
    if (bundleURL == nil) {
        return nil;
    }
    return [self documentFromURL:bundleURL error:nil];
}

+ (NSURL *)defaultExportDirectory {
    NSURL *bundleResources = [NSBundle.mainBundle resourceURL];
    if (bundleResources != nil) {
        NSURL *skillTimelines = [bundleResources URLByAppendingPathComponent:@"SkillTimelines" isDirectory:YES];
        if ([NSFileManager.defaultManager fileExistsAtPath:skillTimelines.path]) {
            return skillTimelines;
        }
    }
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [NSURL fileURLWithPath:[documents stringByAppendingPathComponent:@"SkillTimelines"] isDirectory:YES];
}

@end
