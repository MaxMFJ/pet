#import "PETSpineSocketRegistry.h"

@implementation PETSpineSocketDefinition

- (instancetype)initWithName:(NSString *)name
                        bone:(NSString *)bone
                 localOffset:(vector_float2)localOffset
          localRotationRadians:(float)localRotationRadians {
    self = [super init];
    if (self) {
        _name = [name copy];
        _boneName = [bone copy];
        _localOffset = localOffset;
        _localRotationRadians = localRotationRadians;
    }
    return self;
}

@end

@interface PETSpineSocketRegistry ()

@property (nonatomic, copy) NSDictionary<NSString *, NSArray<PETSpineSocketDefinition *> *> *socketsByProfileId;

@end

@implementation PETSpineSocketRegistry

+ (instancetype)sharedRegistry {
    static PETSpineSocketRegistry *registry = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [[PETSpineSocketRegistry alloc] init];
        [registry reloadFromBundle];
    });
    return registry;
}

- (void)reloadFromBundle {
    NSMutableDictionary<NSString *, NSArray<PETSpineSocketDefinition *> *> *loaded = [NSMutableDictionary dictionary];
    NSURL *bundleRoot = [NSBundle.mainBundle resourceURL];
    NSURL *socketsDirectory = [bundleRoot URLByAppendingPathComponent:@"Combat/sockets" isDirectory:YES];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:socketsDirectory
                                                            includingPropertiesForKeys:nil
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:nil];
    for (NSURL *fileURL in files) {
        if (![fileURL.pathExtension isEqualToString:@"json"]) {
            continue;
        }
        NSData *data = [NSData dataWithContentsOfURL:fileURL];
        if (data == nil) {
            continue;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *root = (NSDictionary *)json;
        NSString *profileId = [root[@"profileId"] isKindOfClass:NSString.class] ? root[@"profileId"] : fileURL.URLByDeletingPathExtension.lastPathComponent;
        NSArray *rawSockets = [root[@"sockets"] isKindOfClass:NSArray.class] ? root[@"sockets"] : @[];
        NSMutableArray<PETSpineSocketDefinition *> *definitions = [NSMutableArray array];
        for (NSDictionary *entry in rawSockets) {
            if (![entry isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSString *name = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : nil;
            NSString *bone = [entry[@"bone"] isKindOfClass:NSString.class] ? entry[@"bone"] : name;
            if (name.length == 0) {
                continue;
            }
            vector_float2 offset = {
                [entry[@"offsetX"] respondsToSelector:@selector(floatValue)] ? [entry[@"offsetX"] floatValue] : 0.0f,
                [entry[@"offsetY"] respondsToSelector:@selector(floatValue)] ? [entry[@"offsetY"] floatValue] : 0.0f
            };
            float rotation = [entry[@"rotation"] respondsToSelector:@selector(floatValue)] ? (float)([entry[@"rotation"] doubleValue] * M_PI / 180.0) : 0.0f;
            [definitions addObject:[[PETSpineSocketDefinition alloc] initWithName:name
                                                                               bone:bone ?: name
                                                                        localOffset:offset
                                                                 localRotationRadians:rotation]];
        }
        if (definitions.count > 0) {
            loaded[profileId] = definitions.copy;
        }
    }
    self.socketsByProfileId = loaded.copy;
}

- (NSArray<NSString *> *)socketNamesForProfileId:(NSString *)profileId {
    NSArray<PETSpineSocketDefinition *> *definitions = self.socketsByProfileId[profileId ?: @""];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (PETSpineSocketDefinition *definition in definitions) {
        [names addObject:definition.name];
    }
    return names.copy;
}

- (PETSpineSocketDefinition *)socketNamed:(NSString *)socketName profileId:(NSString *)profileId {
    for (PETSpineSocketDefinition *definition in self.socketsByProfileId[profileId ?: @""]) {
        if ([definition.name isEqualToString:socketName]) {
            return definition;
        }
    }
    return nil;
}

@end
