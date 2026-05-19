#import "PETSkillPhase.h"

@interface PETSkillPhase ()

@property (nonatomic, copy) NSString *phaseIdentifier;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *animationState;
@property (nonatomic, assign) BOOL movementLock;
@property (nonatomic, assign) CGFloat gravityScale;
@property (nonatomic, copy) NSDictionary<NSString *, id> *casterMotion;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *hitWindows;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *effects;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *transitions;

@end

@implementation PETSkillPhase

- (instancetype)initWithDictionaryRepresentation:(NSDictionary<NSString *,id> *)dictionary {
    self = [super init];
    if (self) {
        NSString *phaseIdentifier = [dictionary[@"phaseId"] isKindOfClass:NSString.class] ? dictionary[@"phaseId"] : @"phase";
        NSString *animationState = [dictionary[@"animationState"] isKindOfClass:NSString.class] ? dictionary[@"animationState"] : @"idle";
        NSArray<NSDictionary<NSString *, id> *> *hitWindows = [dictionary[@"hitWindows"] isKindOfClass:NSArray.class] ? dictionary[@"hitWindows"] : @[];
        NSArray<NSDictionary<NSString *, id> *> *effects = [dictionary[@"effects"] isKindOfClass:NSArray.class] ? dictionary[@"effects"] : @[];
        NSArray<NSDictionary<NSString *, id> *> *transitions = [dictionary[@"transitions"] isKindOfClass:NSArray.class] ? dictionary[@"transitions"] : @[];
        NSDictionary<NSString *, id> *casterMotion = [dictionary[@"casterMotion"] isKindOfClass:NSDictionary.class] ? dictionary[@"casterMotion"] : @{};

        _phaseIdentifier = [phaseIdentifier copy];
        _startTime = MAX(0.0, [dictionary[@"startTime"] doubleValue]);
        _duration = MAX(0.0, [dictionary[@"duration"] doubleValue]);
        _animationState = [animationState copy];
        if (dictionary[@"allowMovementDuringCast"] != nil) {
            _movementLock = ![dictionary[@"allowMovementDuringCast"] boolValue];
        } else {
            _movementLock = [dictionary[@"movementLock"] boolValue];
        }
        NSNumber *gravityScale = [dictionary[@"gravityScale"] respondsToSelector:@selector(doubleValue)] ? dictionary[@"gravityScale"] : nil;
        _gravityScale = gravityScale != nil ? gravityScale.doubleValue : 1.0;
        _casterMotion = [casterMotion copy];
        _hitWindows = [hitWindows copy];
        _effects = [effects copy];
        _transitions = [transitions copy];
    }
    return self;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    return @{
        @"phaseId": self.phaseIdentifier ?: @"phase",
        @"startTime": @(self.startTime),
        @"duration": @(self.duration),
        @"animationState": self.animationState ?: @"idle",
        @"movementLock": @(self.movementLock),
        @"allowMovementDuringCast": @(!self.movementLock),
        @"gravityScale": @(self.gravityScale),
        @"casterMotion": self.casterMotion ?: @{},
        @"hitWindows": self.hitWindows ?: @[],
        @"effects": self.effects ?: @[],
        @"transitions": self.transitions ?: @[]
    };
}

- (NSArray<NSDictionary<NSString *,id> *> *)activeHitWindowsAtPhaseTime:(NSTimeInterval)phaseTime {
    NSMutableArray<NSDictionary<NSString *, id> *> *windows = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *window in self.hitWindows) {
        NSTimeInterval startTime = [window[@"startTime"] doubleValue];
        NSTimeInterval endTime = [window[@"endTime"] doubleValue];
        if (phaseTime + 0.0001 < startTime || phaseTime - 0.0001 > endTime) {
            continue;
        }
        [windows addObject:window];
    }
    return windows.copy;
}

- (CGVector)casterMotionOffsetAtPhaseTime:(NSTimeInterval)phaseTime facingRight:(BOOL)facingRight {
    if (self.casterMotion.count == 0) {
        return CGVectorMake(0.0, 0.0);
    }

    NSTimeInterval startTime = MAX(0.0, [self.casterMotion[@"startTime"] doubleValue]);
    NSTimeInterval endTime = [self.casterMotion[@"endTime"] respondsToSelector:@selector(doubleValue)] ? [self.casterMotion[@"endTime"] doubleValue] : self.duration;
    if (endTime <= startTime) {
        endTime = MAX(startTime, self.duration);
    }
    CGFloat dx = [self.casterMotion[@"dx"] doubleValue];
    CGFloat dy = [self.casterMotion[@"dy"] doubleValue];
    if (![self.casterMotion[@"relativeToFacing"] boolValue] || facingRight) {
        // Keep authored vector as-is.
    } else {
        dx = -dx;
    }

    if (phaseTime <= startTime + 0.0001) {
        return CGVectorMake(0.0, 0.0);
    }
    if (endTime <= startTime + 0.0001) {
        return CGVectorMake(dx, dy);
    }

    CGFloat progress = (CGFloat)((phaseTime - startTime) / (endTime - startTime));
    progress = MIN(MAX(progress, 0.0), 1.0);
    return CGVectorMake(dx * progress, dy * progress);
}

@end
