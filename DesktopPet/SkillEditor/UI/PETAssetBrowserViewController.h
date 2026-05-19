#import <Cocoa/Cocoa.h>

@class PETPetProfile;
@class PETPetManager;

NS_ASSUME_NONNULL_BEGIN

@protocol PETAssetBrowserViewControllerDelegate <NSObject>
- (void)assetBrowserDidSelectProfile:(PETPetProfile *)profile;
- (void)assetBrowserDidSelectAnimation:(NSString *)animationName;
@optional
- (void)assetBrowserDidSelectFXAsset:(NSString *)assetName;
@end

@interface PETAssetBrowserViewController : NSViewController

@property (nonatomic, weak, nullable) id<PETAssetBrowserViewControllerDelegate> browserDelegate;
@property (nonatomic, strong, nullable) PETPetProfile *selectedProfile;

- (instancetype)initWithPetManager:(PETPetManager *)petManager;

@end

NS_ASSUME_NONNULL_END
