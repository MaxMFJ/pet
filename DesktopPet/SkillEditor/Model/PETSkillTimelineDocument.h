#import <Foundation/Foundation.h>

#import "PETSkillTimelineTrack.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const PETSkillTimelineDocumentDidChangeNotification;

@interface PETSkillTimelineDocument : NSObject

@property (nonatomic, copy) NSString *skillIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NSInteger formatVersion;
@property (nonatomic, copy) NSString *characterProfileId;
@property (nonatomic, copy) NSString *characterAnimation;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong) NSMutableArray<PETSkillTimelineTrack *> *tracks;
@property (nonatomic, assign) NSTimeInterval playheadTime;
@property (nonatomic, assign) BOOL loopPlayback;

+ (instancetype)emptyDocument;
+ (instancetype)sampleDocument;

- (PETSkillTimelineTrack *)trackWithType:(PETSkillTimelineTrackType)trackType
                          createIfNeeded:(BOOL)createIfNeeded;
- (void)ensureDefaultTracks;
- (void)notifyChanged;
- (void)applyStateFromDocument:(PETSkillTimelineDocument *)source preservePlayhead:(BOOL)preservePlayhead;

@end

NS_ASSUME_NONNULL_END
