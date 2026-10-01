#import "AppDelegate.h"
#import "MainViewController.h"
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
 self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
 self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[MainViewController new]];
 [self.window makeKeyAndVisible]; return YES;
}
@end
