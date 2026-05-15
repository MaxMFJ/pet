#import "PETEmotionEngine.h"

#import "../Models/PETCharacterEmotion.h"
#import "../Models/PETCharacterIntent.h"
#import "../Models/PETCharacterSnapshot.h"
#import "PETCharacterSemanticConfig.h"

@implementation PETEmotionEngine

- (PETCharacterEmotion *)emotionForIntent:(PETCharacterIntent *)intent
                         previousSnapshot:(PETCharacterSnapshot *)previousSnapshot {
    NSDictionary<NSString *, id> *rule = [[PETCharacterSemanticConfig sharedConfig] emotionRuleForIntentName:intent.name
                                                                                                     actionKey:intent.actionKey];
    NSString *label = [rule[@"label"] isKindOfClass:NSString.class] ? rule[@"label"] : @"alert";
    double valence = [rule[@"valence"] respondsToSelector:@selector(doubleValue)] ? [rule[@"valence"] doubleValue] : 0.10;
    double arousal = [rule[@"arousal"] respondsToSelector:@selector(doubleValue)] ? [rule[@"arousal"] doubleValue] : 0.40;
    BOOL allowsBlend = [rule[@"allowBlend"] respondsToSelector:@selector(boolValue)] ? [rule[@"allowBlend"] boolValue] : YES;

    if (previousSnapshot != nil && allowsBlend) {
        valence = (previousSnapshot.emotionValence * 0.25) + (valence * 0.75);
        arousal = (previousSnapshot.emotionArousal * 0.20) + (arousal * 0.80);
    }

    return [[PETCharacterEmotion alloc] initWithLabel:label valence:valence arousal:arousal];
}

@end
