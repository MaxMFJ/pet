#import "PETSkillTimelineUndoManager.h"

#import "PETSkillTimelineDocument.h"
#import "../Compiler/PETSkillTimelineJSONSerializer.h"

static const NSUInteger PETSkillTimelineUndoLimit = 50;

@interface PETSkillTimelineUndoManager ()

@property (nonatomic, weak) PETSkillTimelineDocument *document;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *undoStack;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *redoStack;
@property (nonatomic, copy, nullable) NSString *lastRecordedFingerprint;

@end

@implementation PETSkillTimelineUndoManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _undoStack = [NSMutableArray array];
        _redoStack = [NSMutableArray array];
    }
    return self;
}

- (BOOL)canUndo {
    return self.undoStack.count > 0;
}

- (BOOL)canRedo {
    return self.redoStack.count > 0;
}

- (void)prepareWithDocument:(PETSkillTimelineDocument *)document {
    self.document = document;
    [self clear];
    [self recordSnapshotNow];
}

- (void)recordSnapshotIfNeeded {
    NSString *fingerprint = [self fingerprintForDocument:self.document];
    if (fingerprint.length > 0 && [fingerprint isEqualToString:self.lastRecordedFingerprint]) {
        return;
    }
    [self recordSnapshotNow];
}

- (void)recordSnapshotNow {
    if (self.document == nil) {
        return;
    }
    NSDictionary *snapshot = [PETSkillTimelineJSONSerializer dictionaryFromDocument:self.document];
    snapshot = [snapshot copy];
    [self.undoStack addObject:snapshot];
    if (self.undoStack.count > PETSkillTimelineUndoLimit) {
        [self.undoStack removeObjectAtIndex:0];
    }
    [self.redoStack removeAllObjects];
    self.lastRecordedFingerprint = [self fingerprintForDocument:self.document];
}

- (BOOL)undo {
    if (!self.canUndo || self.document == nil) {
        return NO;
    }
    NSDictionary *current = [PETSkillTimelineJSONSerializer dictionaryFromDocument:self.document];
    [self.redoStack addObject:current];

    NSDictionary *previous = self.undoStack.lastObject;
    [self.undoStack removeLastObject];
    [self applySnapshot:previous];
    self.lastRecordedFingerprint = [self fingerprintForDocument:self.document];
    return YES;
}

- (BOOL)redo {
    if (!self.canRedo || self.document == nil) {
        return NO;
    }
    NSDictionary *current = [PETSkillTimelineJSONSerializer dictionaryFromDocument:self.document];
    [self.undoStack addObject:current];

    NSDictionary *next = self.redoStack.lastObject;
    [self.redoStack removeLastObject];
    [self applySnapshot:next];
    self.lastRecordedFingerprint = [self fingerprintForDocument:self.document];
    return YES;
}

- (void)clear {
    [self.undoStack removeAllObjects];
    [self.redoStack removeAllObjects];
    self.lastRecordedFingerprint = nil;
}

- (void)applySnapshot:(NSDictionary<NSString *, id> *)snapshot {
    PETSkillTimelineDocument *restored = [PETSkillTimelineJSONSerializer documentFromDictionary:snapshot];
    if (restored == nil) {
        return;
    }
    [self.document applyStateFromDocument:restored preservePlayhead:YES];
    [self.document notifyChanged];
}

- (NSString *)fingerprintForDocument:(PETSkillTimelineDocument *)document {
    if (document == nil) {
        return @"";
    }
    NSDictionary *dictionary = [PETSkillTimelineJSONSerializer dictionaryFromDocument:document];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingSortedKeys error:nil];
    if (data == nil) {
        return @"";
    }
    return [[NSString alloc] initWithFormat:@"%lu-%@", (unsigned long)data.length, data];
}

@end
