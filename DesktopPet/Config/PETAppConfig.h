#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PETAppConfig : NSObject

@property (nonatomic, copy) NSString *aiBaseURLString;
@property (nonatomic, assign) BOOL cognitionEnabled;
@property (nonatomic, assign) BOOL OCRDesktopEnabled;
@property (nonatomic, assign) NSInteger maxConcurrentPets;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *petInstanceRecords;

- (void)loadDefaults;
- (void)persist;

@end

NS_ASSUME_NONNULL_END
