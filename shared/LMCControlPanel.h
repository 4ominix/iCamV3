#import <UIKit/UIKit.h>
#import "LMCConfig.h"
@interface LMCControlPanel : UIView
@property(nonatomic,copy) void (^configurationChanged)(LMCConfig *config, NSError *error);
- (void)refresh;
@end
