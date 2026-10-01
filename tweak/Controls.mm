#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import "LMCConfig.h"
#import "LMCControlPanel.h"

@interface LMCPassthroughWindow : UIWindow
@end
@implementation LMCPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    return (hit==self || hit==self.rootViewController.view)?nil:hit;
}
@end
@interface LMCFloatingController : UIViewController
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) UIView *container;
@property(nonatomic,strong) LMCControlPanel *panel;
@property(nonatomic,strong) UILabel *errorLabel;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) int lockToken;
@property(nonatomic) BOOL lockNotificationAvailable;
@end
@implementation LMCFloatingController
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.clearColor;
    self.bubble=[UIButton buttonWithType:UIButtonTypeSystem];self.bubble.frame=CGRectMake(16,200,54,54);
    self.bubble.backgroundColor=[UIColor colorWithWhite:.06 alpha:.95];self.bubble.layer.cornerRadius=27;
    self.bubble.layer.borderColor=UIColor.systemTealColor.CGColor;self.bubble.layer.borderWidth=2;
    [self.bubble setTitle:@"✥" forState:UIControlStateNormal];self.bubble.titleLabel.font=[UIFont systemFontOfSize:30];
    [self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [self.view addSubview:self.bubble];
    self.container=[[UIView alloc] initWithFrame:CGRectMake(78,130,270,390)];self.container.hidden=YES;
    self.panel=[[LMCControlPanel alloc] initWithFrame:CGRectMake(0,0,270,350)];[self.container addSubview:self.panel];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];close.frame=CGRectMake(228,0,40,35);
    [close setTitle:@"×" forState:UIControlStateNormal];[close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.container addSubview:close];
    self.errorLabel=[[UILabel alloc] initWithFrame:CGRectMake(0,352,270,38)];self.errorLabel.textColor=UIColor.systemRedColor;
    self.errorLabel.font=[UIFont systemFontOfSize:11];self.errorLabel.numberOfLines=2;[self.container addSubview:self.errorLabel];
    [self.view addSubview:self.container];__weak typeof(self) weakSelf=self;
    self.panel.configurationChanged=^(LMCConfig *c,NSError *e){weakSelf.errorLabel.text=e.localizedDescription?:@"";};
    self.lockToken=-1;
    self.lockNotificationAvailable=notify_register_dispatch("com.apple.springboard.lockstate",&_lockToken,
        dispatch_get_main_queue(),^(int token){[weakSelf refreshVisibility];})==NOTIFY_STATUS_OK;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[weakSelf refreshVisibility];}];
    [self refreshVisibility];
}
- (void)refreshVisibility {
    uint64_t locked=1;
    if(self.lockNotificationAvailable)notify_get_state(self.lockToken,&locked);
    BOOL visible=[LMCConfig load].enabled && !locked;
    self.bubble.hidden=!visible;if(!visible)self.container.hidden=YES;
    [self.panel refresh];
}
- (void)togglePanel {
    self.container.hidden=!self.container.hidden;[self.panel refresh];
    CGFloat x=MIN(MAX(12,self.bubble.frame.origin.x+60),MAX(12,self.view.bounds.size.width-282));
    CGFloat y=MIN(MAX(60,self.bubble.frame.origin.y-70),MAX(60,self.view.bounds.size.height-420));
    self.container.frame=CGRectMake(x,y,270,390);
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGPoint delta=[gesture translationInView:self.view];CGPoint center=self.bubble.center;
    center.x=MIN(MAX(30,center.x+delta.x),self.view.bounds.size.width-30);
    center.y=MIN(MAX(70,center.y+delta.y),self.view.bounds.size.height-70);
    self.bubble.center=center;[gesture setTranslation:CGPointZero inView:self.view];
    if(!self.container.hidden){self.container.hidden=YES;[self togglePanel];}
}
- (void)dealloc { if(self.lockNotificationAvailable)notify_cancel(self.lockToken);[self.timer invalidate]; }
@end
static LMCPassthroughWindow *overlay;
static id launchObserver;
static void ShowControls(void){
    if(overlay)return;overlay=[[LMCPassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    overlay.windowLevel=UIWindowLevelAlert+1;overlay.rootViewController=[LMCFloatingController new];
    // Do not become key: underlying applications keep keyboard/touch ownership.
    overlay.hidden=NO;
}
__attribute__((constructor))static void initControls(void){@autoreleasepool{
    launchObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ShowControls();}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(UIApplication.sharedApplication)ShowControls();});
}}
