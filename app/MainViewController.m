#import "MainViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "LMCConfig.h"
#import "LMCRender.h"
#import "LMCControlPanel.h"

@interface MainViewController () <PHPickerViewControllerDelegate>
@property(nonatomic,strong) LMCConfig *config;
@property(nonatomic,strong) UIImageView *preview;
@property(nonatomic,strong) CIContext *context;
@property(nonatomic,strong) CIImage *still;
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerItemVideoOutput *videoOutput;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic,strong) id endObserver;
@property(nonatomic,strong) NSTimer *poll;
@property(nonatomic,strong) NSDate *configDate;
@property(nonatomic,strong) UISwitch *enabledSwitch,*loopSwitch,*mirrorSwitch;
@property(nonatomic,strong) UISegmentedControl *modeControl,*rotationControl;
@property(nonatomic,strong) UILabel *status,*diagnostics;
@property(nonatomic,strong) UIButton *chooseButton;
@property(nonatomic,strong) LMCControlPanel *panel;
@property(nonatomic) BOOL importing;
@property(nonatomic) double gestureX,gestureY,gestureZoom;
@property(nonatomic) BOOL gesturing;
@end
@implementation MainViewController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"iCamV3";self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=[UIColor colorWithWhite:.055 alpha:1];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewBackground:)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewForeground:)
        name:UIApplicationWillEnterForegroundNotification object:nil];
    self.config=[LMCConfig load];self.context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;
    stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
      [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
      [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
      [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
      [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
      [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
      [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:18],
      [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-18],
      [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]]];
    self.preview=[UIImageView new];self.preview.backgroundColor=UIColor.blackColor;self.preview.clipsToBounds=YES;
    self.preview.contentMode=UIViewContentModeScaleAspectFit;self.preview.layer.cornerRadius=16;
    self.preview.userInteractionEnabled=YES;
    [self.preview addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPreview:)]];
    [self.preview addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchPreview:)]];
    [self.preview.heightAnchor constraintEqualToConstant:320].active=YES;[stack addArrangedSubview:self.preview];
    self.chooseButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.chooseButton setTitle:@"Chọn ảnh hoặc video" forState:UIControlStateNormal];
    self.chooseButton.titleLabel.font=[UIFont boldSystemFontOfSize:19];[self.chooseButton addTarget:self action:@selector(chooseMedia) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.chooseButton];
    self.enabledSwitch=[self addSwitch:@"Bật camera ảo" stack:stack];
    self.loopSwitch=[self addSwitch:@"Lặp video" stack:stack];self.mirrorSwitch=[self addSwitch:@"Lật ngang" stack:stack];
    self.modeControl=[[UISegmentedControl alloc] initWithItems:@[@"Fit",@"Fill"]];
    self.rotationControl=[[UISegmentedControl alloc] initWithItems:@[@"0°",@"90°",@"180°",@"270°"]];
    for(UISegmentedControl *s in @[self.modeControl,self.rotationControl]){
        [s addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];[stack addArrangedSubview:s];}
    self.panel=[LMCControlPanel new];[stack addArrangedSubview:self.panel];
    __weak typeof(self) weakSelf=self;
    self.panel.configurationChanged=^(LMCConfig *c,NSError *error){
        weakSelf.config=c;[weakSelf syncControls];[weakSelf drawPreview];
        weakSelf.status.text=error?[NSString stringWithFormat:@"Lỗi: %@",error.localizedDescription]:@"Đã lưu vị trí và zoom.";};
    self.status=[self label];self.diagnostics=[self label];[stack addArrangedSubview:self.status];[stack addArrangedSubview:self.diagnostics];
    self.status.text=@"Chọn nguồn media; bảng mũi tên dùng để dịch chuyển hình ảnh.";
    [self syncControls];[self reloadPreview];[self updateDiagnostics];
}
- (UILabel *)label { UILabel *l=[UILabel new];l.numberOfLines=0;l.textColor=UIColor.lightGrayColor;
    l.font=[UIFont systemFontOfSize:13];l.textAlignment=NSTextAlignmentCenter;return l; }
- (UISwitch *)addSwitch:(NSString *)text stack:(UIStackView *)stack {
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;
    UILabel *label=[UILabel new];label.text=text;label.textColor=UIColor.whiteColor;
    UISwitch *s=[UISwitch new];[s addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:label];[row addArrangedSubview:s];[stack addArrangedSubview:row];return s;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];self.navigationController.navigationBar.barStyle=UIBarStyleBlack;
    self.config=[LMCConfig load];[self syncControls];[self reloadPreview];
    [self.poll invalidate];__weak typeof(self) weakSelf=self;
    self.poll=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weakSelf pollConfiguration];}];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];[self.poll invalidate];self.poll=nil;[self stopVideo];
}
- (void)previewBackground:(NSNotification *)notification { self.gesturing=NO;[self stopVideo]; }
- (void)previewForeground:(NSNotification *)notification {
    if(self.view.window && !self.presentedViewController){self.config=[LMCConfig load];[self syncControls];[self reloadPreview];}
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self];[self.poll invalidate];[self stopVideo]; }
- (void)syncControls {
    self.enabledSwitch.on=self.config.enabled;self.loopSwitch.on=self.config.loop;self.mirrorSwitch.on=self.config.mirror;
    self.modeControl.selectedSegmentIndex=self.config.contentMode;self.rotationControl.selectedSegmentIndex=self.config.rotation/90;
    [self.panel refresh];
}
- (void)pollConfiguration {
    if(self.gesturing)return;
    NSDate *date=[NSFileManager.defaultManager attributesOfItemAtPath:LMCConfig.preferencesPath error:nil][NSFileModificationDate];
    if(date && ![date isEqual:self.configDate]){
        NSString *previous=self.config.resolvedMediaPath;self.config=[LMCConfig load];self.configDate=date;[self syncControls];
        if(![previous isEqual:self.config.resolvedMediaPath])[self reloadPreview];else [self drawPreview];
    }[self updateDiagnostics];
}
- (void)updateDiagnostics {
    NSMutableArray *lines=[NSMutableArray new];
    for(NSString *host in @[@"mediaserverd",@"cameracaptured"]){
        NSString *path=[LMCConfig.baseDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"CameraStatus.%@.plist",host]];
        NSDictionary *d=[NSDictionary dictionaryWithContentsOfFile:path];
        NSTimeInterval stamp=[d[@"Timestamp"] doubleValue];
        if(d && NSDate.date.timeIntervalSince1970-stamp<10){
            [lines addObject:[NSString stringWithFormat:@"%@: %@; hooks=%@; frame=%@",host,d[@"State"]?:@"?",d[@"Hooks"]?:@0,d[@"Replaced"]?:@0]];
        }
    }
    self.diagnostics.text=lines.count?[lines componentsJoinedByString:@"\n"]:
       @"Chưa có tín hiệu từ tiến trình camera. Mở Camera để kiểm tra; nếu vẫn trống, kiểm tra tweak injection của RootHide. Lưu cấu hình không đồng nghĩa với hook đã hoạt động.";
}
- (void)chooseMedia {
    if(self.importing)return;
    PHPickerConfiguration *c=[[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    c.selectionLimit=1;c.preferredAssetRepresentationMode=PHPickerConfigurationAssetRepresentationModeCurrent;
    c.filter=[PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter,PHPickerFilter.videosFilter]];
    PHPickerViewController *picker=[[PHPickerViewController alloc] initWithConfiguration:c];picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];PHPickerResult *r=results.firstObject;if(!r)return;
    NSItemProvider *provider=r.itemProvider;BOOL movie=[provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier];
    NSString *type=movie?UTTypeMovie.identifier:UTTypeImage.identifier;
    self.importing=YES;self.chooseButton.enabled=NO;self.status.text=@"Đang nhập media (ảnh/video iCloud có thể cần tải xuống)…";
    [provider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url,NSError *loadError){
        NSError *error=loadError;NSString *name=nil;NSString *destination=nil;
        NSFileManager *fm=NSFileManager.defaultManager;
        if(url && !error){
            NSString *ext=url.pathExtension.length?url.pathExtension:(movie?@"mov":@"jpg");
            name=[NSString stringWithFormat:@"source.%@.%@",NSUUID.UUID.UUIDString,ext];
            destination=[LMCConfig.baseDirectory stringByAppendingPathComponent:name];
            if([fm createDirectoryAtPath:LMCConfig.baseDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]){
                // The picker URL is temporary: copy BEFORE the completion handler returns.
                [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination] error:&error];
                if(!error){[fm setAttributes:@{NSFilePosixPermissions:@0644,NSFileProtectionKey:NSFileProtectionNone} ofItemAtPath:destination error:&error];}
                if(!error){
                    BOOL valid=movie?[[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:destination] options:nil] tracksWithMediaType:AVMediaTypeVideo].count>0:
                      [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:destination] options:@{kCIImageApplyOrientationProperty:@YES}]!=nil;
                    if(!valid)error=[NSError errorWithDomain:@"iCamV3" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Media không có dữ liệu ảnh/video đọc được."}];
                }
            }
        }
        if(!url && !error)error=[NSError errorWithDomain:@"iCamV3" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Thư viện không trả về tệp media."}];
        NSError *importError=error;
        dispatch_async(dispatch_get_main_queue(),^{
            self.importing=NO;self.chooseButton.enabled=YES;
            if(importError){if(destination)[fm removeItemAtPath:destination error:nil];self.status.text=[NSString stringWithFormat:@"Lỗi nhập media: %@",importError.localizedDescription];return;}
            LMCConfig *next=[LMCConfig load];NSString *oldPath=next.resolvedMediaPath;
            next.mediaPath=name;next.mediaType=movie?@"video":@"image";
            NSError *saveError=nil;
            if(![next save:&saveError]){
                [fm removeItemAtPath:destination error:nil];self.status.text=[NSString stringWithFormat:@"Lỗi lưu cấu hình: %@",saveError.localizedDescription];return;
            }
            self.config=next;[self syncControls];[self reloadPreview];
            // The managed previous source can be removed only after the atomic config commit.
            if(oldPath.length && ![oldPath isEqual:destination])[fm removeItemAtPath:oldPath error:nil];
            self.status.text=@"Đã nhập media và lưu cấu hình. Mở Camera để xem trạng thái xử lý frame.";
        });
    }];
}
- (void)changed:(id)sender {
    LMCConfig *next=[LMCConfig load];
    // Modify only the control the user touched, preserving newer floating-panel changes.
    if(sender==self.enabledSwitch)next.enabled=self.enabledSwitch.on;
    else if(sender==self.loopSwitch)next.loop=self.loopSwitch.on;
    else if(sender==self.mirrorSwitch)next.mirror=self.mirrorSwitch.on;
    else if(sender==self.modeControl)next.contentMode=self.modeControl.selectedSegmentIndex;
    else if(sender==self.rotationControl)next.rotation=self.rotationControl.selectedSegmentIndex*90;
    if(next.enabled && ![NSFileManager.defaultManager isReadableFileAtPath:next.resolvedMediaPath]){
        self.status.text=@"Hãy chọn ảnh/video đọc được trước khi bật camera ảo.";[self syncControls];return;
    }
    NSError *e=nil;if(![next save:&e]){self.status.text=[NSString stringWithFormat:@"Lỗi lưu: %@",e.localizedDescription];[self syncControls];return;}
    self.config=next;[self syncControls];self.status.text=@"Đã lưu. Kiểm tra trạng thái hook bên dưới khi mở Camera.";[self drawPreview];
    if(self.player && self.config.loop && self.player.currentItem.status==AVPlayerItemStatusReadyToPlay &&
       CMTimeCompare(self.player.currentTime,self.player.currentItem.duration)>=0){[self.player seekToTime:kCMTimeZero];[self.player play];}
}
- (void)stopVideo {
    [self.displayLink invalidate];self.displayLink=nil;[self.player pause];self.player=nil;self.videoOutput=nil;
    if(self.endObserver){[NSNotificationCenter.defaultCenter removeObserver:self.endObserver];self.endObserver=nil;}
}
- (void)reloadPreview {
    [self stopVideo];self.still=nil;self.preview.image=nil;NSString *path=self.config.resolvedMediaPath;
    if(![NSFileManager.defaultManager isReadableFileAtPath:path])return;
    if([self.config.mediaType isEqual:@"image"]){self.still=[CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:path] options:@{kCIImageApplyOrientationProperty:@YES}];[self drawPreview];}
    else if([self.config.mediaType isEqual:@"video"]){
        AVPlayerItem *item=[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
        self.videoOutput=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
        [item addOutput:self.videoOutput];self.player=[AVPlayer playerWithPlayerItem:item];
        self.player.muted=YES; // virtual camera supplies video frames only, not speaker/microphone audio
        __weak typeof(self) weakSelf=self;
        self.endObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            if(weakSelf.config.loop){[weakSelf.player seekToTime:kCMTimeZero completionHandler:^(BOOL finished){if(finished)[weakSelf.player play];}];}
        }];
        self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];self.displayLink.preferredFramesPerSecond=15;
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];[self.player play];
    }
}
- (void)tick:(CADisplayLink *)link {
    CMTime time=[self.videoOutput itemTimeForHostTime:CACurrentMediaTime()];
    if([self.videoOutput hasNewPixelBufferForItemTime:time]){
        CVPixelBufferRef pixel=[self.videoOutput copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
        if(pixel){CIImage *image=[CIImage imageWithCVPixelBuffer:pixel];
            // AVPlayerItemVideoOutput returns decoded track pixels; respect the track orientation.
            AVAssetTrack *track=[self.player.currentItem.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
            self.still=[image imageByApplyingTransform:track?track.preferredTransform:CGAffineTransformIdentity];
            [self drawPreview];CVPixelBufferRelease(pixel);}
    }
    if(self.player.currentItem.status==AVPlayerItemStatusFailed)self.status.text=[NSString stringWithFormat:@"Lỗi phát video: %@",self.player.currentItem.error.localizedDescription];
}
- (void)drawPreview {
    if(!self.still)return;
    @try { // Render a fixed 3:4 viewport; never rotate the Auto Layout preview container.
        CGSize size=CGSizeMake(360,480);CIImage *out=LMCComposeImage(self.still,size,self.config);if(!out)return;
        CGImageRef cg=[self.context createCGImage:out fromRect:CGRectMake(0,0,size.width,size.height)];
        if(cg){self.preview.image=[UIImage imageWithCGImage:cg];CGImageRelease(cg);}
    } @catch(NSException *e){self.status.text=[NSString stringWithFormat:@"Lỗi xem trước: %@",e.reason];}
}
- (void)commitGesture {
    NSError *error=nil;
    LMCConfig *latest=[LMCConfig load];
    latest.offsetX=self.config.offsetX;latest.offsetY=self.config.offsetY;latest.zoom=self.config.zoom;
    self.config=latest;
    if(![latest save:&error]){
        self.config=[LMCConfig load];self.status.text=[NSString stringWithFormat:@"Lỗi lưu vị trí: %@",error.localizedDescription];
    }else self.status.text=@"Đã lưu vị trí và zoom.";
    [self syncControls];[self drawPreview];
}
- (void)panPreview:(UIPanGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan){self.gesturing=YES;self.config=[LMCConfig load];self.gestureX=self.config.offsetX;self.gestureY=self.config.offsetY;}
    CGPoint delta=[gesture translationInView:self.preview];
    // The displayed 3:4 viewport can be letterboxed inside the fixed preview view.
    CGFloat scale=MIN(self.preview.bounds.size.width/360,self.preview.bounds.size.height/480);
    self.config.offsetX=fmax(-2,fmin(2,self.gestureX+delta.x/MAX(1,360*scale)));
    self.config.offsetY=fmax(-2,fmin(2,self.gestureY+delta.y/MAX(1,480*scale)));
    [self drawPreview];
    if(gesture.state==UIGestureRecognizerStateEnded){self.gesturing=NO;[self commitGesture];}
    else if(gesture.state==UIGestureRecognizerStateCancelled){self.gesturing=NO;self.config=[LMCConfig load];[self drawPreview];}
}
- (void)pinchPreview:(UIPinchGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan){self.gesturing=YES;self.config=[LMCConfig load];self.gestureZoom=self.config.zoom;}
    self.config.zoom=fmax(.25,fmin(8,self.gestureZoom*gesture.scale));[self drawPreview];
    if(gesture.state==UIGestureRecognizerStateEnded){self.gesturing=NO;[self commitGesture];}
    else if(gesture.state==UIGestureRecognizerStateCancelled){self.gesturing=NO;self.config=[LMCConfig load];[self drawPreview];}
}
@end
