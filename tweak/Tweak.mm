#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <substrate.h>
#import <sys/stat.h>
#import "LMCConfig.h"
#import "LMCRender.h"

static unsigned gHooks=0;
static unsigned long long gReplaced=0;
// Camera callbacks never decode video, wait on a serial queue, or run Core Image.
static BOOL LMCCopyPixels(CVPixelBufferRef src,CVPixelBufferRef dst) {
    if(CVPixelBufferGetPixelFormatType(src)!=CVPixelBufferGetPixelFormatType(dst) ||
       CVPixelBufferGetWidth(src)!=CVPixelBufferGetWidth(dst) || CVPixelBufferGetHeight(src)!=CVPixelBufferGetHeight(dst))return NO;
    if(CVPixelBufferLockBaseAddress(src,kCVPixelBufferLock_ReadOnly)!=kCVReturnSuccess)return NO;
    if(CVPixelBufferLockBaseAddress(dst,0)!=kCVReturnSuccess){CVPixelBufferUnlockBaseAddress(src,kCVPixelBufferLock_ReadOnly);return NO;}
    BOOL ok=YES;size_t planes=CVPixelBufferGetPlaneCount(src);
    if(planes!=CVPixelBufferGetPlaneCount(dst))ok=NO;
    // Preflight every plane BEFORE writing any destination byte: fail-safe keeps untouched real frame.
    for(size_t p=0;p<(planes?planes:1)&&ok;p++){
        size_t sw=planes?CVPixelBufferGetWidthOfPlane(src,p):CVPixelBufferGetWidth(src);
        size_t dw=planes?CVPixelBufferGetWidthOfPlane(dst,p):CVPixelBufferGetWidth(dst);
        size_t sh=planes?CVPixelBufferGetHeightOfPlane(src,p):CVPixelBufferGetHeight(src);
        size_t dh=planes?CVPixelBufferGetHeightOfPlane(dst,p):CVPixelBufferGetHeight(dst);
        size_t sb=planes?CVPixelBufferGetBytesPerRowOfPlane(src,p):CVPixelBufferGetBytesPerRow(src);
        size_t db=planes?CVPixelBufferGetBytesPerRowOfPlane(dst,p):CVPixelBufferGetBytesPerRow(dst);
        void *s=planes?CVPixelBufferGetBaseAddressOfPlane(src,p):CVPixelBufferGetBaseAddress(src);
        void *d=planes?CVPixelBufferGetBaseAddressOfPlane(dst,p):CVPixelBufferGetBaseAddress(dst);
        size_t bytes=planes?(p==0?sw:sw*2):sw*4;
        if(!s||!d||sw!=dw||sh!=dh||sb<bytes||db<bytes)ok=NO;
    }
    if(ok)for(size_t p=0;p<(planes?planes:1);p++){
        size_t w=planes?CVPixelBufferGetWidthOfPlane(src,p):CVPixelBufferGetWidth(src);
        size_t h=planes?CVPixelBufferGetHeightOfPlane(src,p):CVPixelBufferGetHeight(src);
        size_t sb=planes?CVPixelBufferGetBytesPerRowOfPlane(src,p):CVPixelBufferGetBytesPerRow(src);
        size_t db=planes?CVPixelBufferGetBytesPerRowOfPlane(dst,p):CVPixelBufferGetBytesPerRow(dst);
        const uint8_t *s=(const uint8_t *)(planes?CVPixelBufferGetBaseAddressOfPlane(src,p):CVPixelBufferGetBaseAddress(src));
        uint8_t *d=(uint8_t *)(planes?CVPixelBufferGetBaseAddressOfPlane(dst,p):CVPixelBufferGetBaseAddress(dst));
        size_t bytes=planes?(p==0?w:w*2):w*4;
        for(size_t y=0;y<h;y++)memcpy(d+y*db,s+y*sb,bytes);
    }
    CVPixelBufferUnlockBaseAddress(dst,0);CVPixelBufferUnlockBaseAddress(src,kCVPixelBufferLock_ReadOnly);return ok;
}

@interface LMCFrameProvider : NSObject
+ (instancetype)shared;
- (void)reload;
- (void)renderIntoSampleBuffer:(CMSampleBufferRef)sample;
@end
@interface LMCCanvas : NSObject {
@public
    size_t width,height;
    OSType format;
    CVPixelBufferPoolRef pool;
    CVPixelBufferRef cached;
}
@end
@implementation LMCCanvas
- (void)dealloc { if(cached)CVPixelBufferRelease(cached);if(pool)CVPixelBufferPoolRelease(pool); }
@end
@implementation LMCFrameProvider {
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    CIContext *_context;
    LMCConfig *_config;
    CIImage *_stillImage,*_videoImage;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_output;
    CGAffineTransform _videoTransform;
    CMSampleBufferRef _pending;
    double _videoOrigin,_firstPTS,_videoEnd,_frameDuration;
    NSString *_loadedPath,*_state;
    double _lastPoll,_lastStatus;
    os_unfair_lock _lock;
    NSMutableDictionary<NSString *,LMCCanvas *> *_canvases;
    BOOL _enabled;
    BOOL _needsRender,_wasActive;
    double _lastCamera;
}
+ (instancetype)shared { static LMCFrameProvider *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];});return p; }
- (instancetype)init {
    if((self=[super init])){
        _lock=OS_UNFAIR_LOCK_INIT;_queue=dispatch_queue_create("com.icamv3.frames",DISPATCH_QUEUE_SERIAL);
        _canvases=[NSMutableDictionary new];
        // Prewarm the two dimensions observed in the supplied traces, including still capture.
        for(NSArray *size in @[@[@1080,@1440],@[@1584,@1188]]){
            LMCCanvas *canvas=[LMCCanvas new];canvas->width=[size[0] unsignedIntegerValue];canvas->height=[size[1] unsignedIntegerValue];
            canvas->format=kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
            NSString *key=[NSString stringWithFormat:@"%zu:%zu:%u",canvas->width,canvas->height,(unsigned)canvas->format];
            _canvases[key]=canvas;
        }
        _context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
        _state=@"loaded";_timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,_queue);
        dispatch_source_set_timer(_timer,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_SEC/30,NSEC_PER_SEC/300);
        dispatch_source_set_event_handler(_timer,^{@autoreleasepool{@try{[self produceFrame];}
           @catch(NSException *e){self->_state=[@"render-error: " stringByAppendingString:e.reason?:@"unknown"];[self clearCache];}}});
        dispatch_resume(_timer);[self reload];
    }return self;
}
- (void)clearCache {
    os_unfair_lock_lock(&_lock);
    @try {for(LMCCanvas *canvas in _canvases.allValues){if(canvas->cached){CVPixelBufferRelease(canvas->cached);canvas->cached=NULL;}}}
    @finally {os_unfair_lock_unlock(&_lock);}
    _needsRender=YES;
}
- (void)clearReader {
    if(_pending){CFRelease(_pending);_pending=NULL;}
    [_reader cancelReading];_reader=nil;_output=nil;_videoImage=nil;
}
- (void)reload { dispatch_async(_queue,^{@autoreleasepool{ @try{[self loadConfig];}
    @catch(NSException *e){self->_state=@"config-error";[self clearCache];}}}); }
- (void)loadConfig {
    LMCConfig *n=[LMCConfig load];NSString *path=n.resolvedMediaPath;
    BOOL sourceChanged=!_config || ![path isEqual:_loadedPath] || ![n.mediaType isEqual:_config.mediaType] || n.enabled!=_config.enabled;
    BOOL transformChanged=!_config || n.zoom!=_config.zoom || n.offsetX!=_config.offsetX || n.offsetY!=_config.offsetY ||
       n.rotation!=_config.rotation || n.mirror!=_config.mirror || n.contentMode!=_config.contentMode;
    _config=n;os_unfair_lock_lock(&_lock);_enabled=n.enabled;os_unfair_lock_unlock(&_lock);
    if(n.enabled && ![NSFileManager.defaultManager isReadableFileAtPath:path]){
        _loadedPath=@"";_stillImage=nil;[self clearReader];[self clearCache];_state=@"source-unreadable";return;
    }
    if(sourceChanged)[self clearCache];
    if(transformChanged)_needsRender=YES;
    if(!sourceChanged)return;
    _loadedPath=path.copy;_stillImage=nil;[self clearReader];
    if(!n.enabled){_state=@"disabled";return;}
    if(![NSFileManager.defaultManager isReadableFileAtPath:path]){_state=@"source-unreadable";return;}
    if([n.mediaType isEqual:@"image"]){
        _stillImage=[CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:path] options:@{kCIImageApplyOrientationProperty:@YES}];
        _state=_stillImage?@"source-ready":@"image-decode-failed";
    }else if([n.mediaType isEqual:@"video"])[self startReader];else _state=@"invalid-media-type";
}
- (BOOL)startReader {
    [self clearReader];
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:_loadedPath] options:nil];
    AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if(!track){_state=@"video-track-missing";return NO;}
    NSError *e=nil;_reader=[[AVAssetReader alloc] initWithAsset:asset error:&e];
    _videoTransform=track.preferredTransform;
    _output=[[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];
    _output.alwaysCopiesSampleData=NO;
    if(!_reader || ![_reader canAddOutput:_output]){_reader=nil;_output=nil;_state=@"video-reader-failed";return NO;}
    [_reader addOutput:_output];if(![_reader startReading]){_state=_reader.error.localizedDescription?:@"video-start-failed";[self clearReader];return NO;}
    float fps=track.nominalFrameRate;
    _frameDuration=isfinite(fps)&&fps>0 ? 1.0/fps : 1.0/30.0;
    _videoOrigin=CACurrentMediaTime();_firstPTS=NAN;_videoEnd=0;_state=@"source-ready";return YES;
}
- (CIImage *)nextSource {
    if(_stillImage)return _stillImage;
    if(!_output)return nil;
    // Use presentation timestamps, not hook-call count or nominal frame rate (VFR videos work).
    double elapsed=CACurrentMediaTime()-_videoOrigin;
    BOOL restarted=NO;
    for(int i=0;i<12;i++){
        if(!_pending)_pending=[_output copyNextSampleBuffer];
        if(!_pending){
            if(_reader.status==AVAssetReaderStatusCompleted){
                // Read-ahead EOF is NOT the end of the last frame's display interval.
                // This matters particularly for a single-frame or very short video.
                if(_videoImage && elapsed<_videoEnd)return _videoImage;
                if(_config.loop && !restarted){
                    restarted=YES;if(![self startReader])return nil;elapsed=0;continue;
                }
                _state=@"video-ended";return nil; // do not keep replacing with a frozen EOF frame
            }
            if(_reader.status==AVAssetReaderStatusFailed)_state=_reader.error.localizedDescription?:@"video-decode-failed";
            return nil;
        }
        double pts=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(_pending));
        if(!isfinite(pts))pts=isfinite(_firstPTS)?_firstPTS:0;
        if(!isfinite(_firstPTS))_firstPTS=pts;
        if(_videoImage && pts-_firstPTS>elapsed)break;
        CVPixelBufferRef p=CMSampleBufferGetImageBuffer(_pending);
        if(p){
            _videoImage=[[CIImage imageWithCVPixelBuffer:p] imageByApplyingTransform:_videoTransform];
            double duration=CMTimeGetSeconds(CMSampleBufferGetDuration(_pending));
            if(!isfinite(duration)||duration<=0)duration=_frameDuration;
            _videoEnd=MAX(_videoEnd,MAX(0,pts-_firstPTS)+duration);
        }
        CFRelease(_pending);_pending=NULL;
    }return _videoImage;
}
- (void)writeStatus {
    double now=NSDate.date.timeIntervalSince1970;if(now-_lastStatus<2)return;_lastStatus=now;
    NSString *host=NSProcessInfo.processInfo.processName;
    NSString *path=[LMCConfig.baseDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"CameraStatus.%@.plist",host]];
    NSDictionary *d=@{@"Timestamp":@(now),@"PID":@(NSProcessInfo.processInfo.processIdentifier),
       @"State":_state?:@"unknown",@"Hooks":@(__atomic_load_n(&gHooks,__ATOMIC_RELAXED)),
       @"Replaced":@(__atomic_load_n(&gReplaced,__ATOMIC_RELAXED))};
    if([d writeToFile:path atomically:YES])chmod(path.fileSystemRepresentation,0644);
}
- (void)produceFrame {
    double now=CACurrentMediaTime();if(now-_lastPoll>.5){_lastPoll=now;[self loadConfig];}
    [self writeStatus];if(!_config.enabled)return;
    NSArray<LMCCanvas *> *canvases=nil;double lastCamera=0;
    os_unfair_lock_lock(&_lock);
    @try {canvases=_canvases.allValues;lastCamera=_lastCamera;}
    @finally {os_unfair_lock_unlock(&_lock);}
    BOOL active=now-lastCamera<2;
    if(!active && !_needsRender){_wasActive=NO;return;} // idle: no continuous GPU/video decoding
    if(active && !_wasActive && [_config.mediaType isEqual:@"video"])[self startReader];
    _wasActive=active;
    CIImage *src=[self nextSource];if(!src){[self clearCache];return;}
    for(LMCCanvas *canvas in canvases){
    size_t w=canvas->width,h=canvas->height;OSType format=canvas->format;
    CIImage *out=LMCComposeImage(src,CGSizeMake(w,h),_config);if(!out){[self clearCache];return;}
    if(!canvas->pool){
        NSDictionary *attrs=@{(id)kCVPixelBufferWidthKey:@(w),(id)kCVPixelBufferHeightKey:@(h),
          (id)kCVPixelBufferPixelFormatTypeKey:@(format),(id)kCVPixelBufferIOSurfacePropertiesKey:@{}};
        if(CVPixelBufferPoolCreate(kCFAllocatorDefault,NULL,(__bridge CFDictionaryRef)attrs,&canvas->pool)!=kCVReturnSuccess){_state=@"pixel-pool-failed";continue;}
    }
    CVPixelBufferRef scratch=NULL;
    NSDictionary *limit=@{(id)kCVPixelBufferPoolAllocationThresholdKey:@3};
    if(CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,canvas->pool,(__bridge CFDictionaryRef)limit,&scratch)!=kCVReturnSuccess)continue;
    @try {
        // Render in scratch. A failed render cannot partially overwrite the real camera frame.
        [_context render:out toCVPixelBuffer:scratch bounds:CGRectMake(0,0,w,h) colorSpace:NULL];
        os_unfair_lock_lock(&_lock);CVPixelBufferRef old=canvas->cached;canvas->cached=CVPixelBufferRetain(scratch);os_unfair_lock_unlock(&_lock);
        if(old)CVPixelBufferRelease(old);_state=@"render-ready";
    } @finally {CVPixelBufferRelease(scratch);}
    }
    _needsRender=NO;
}
- (void)renderIntoSampleBuffer:(CMSampleBufferRef)sample {
    if(!sample || !CMSampleBufferDataIsReady(sample))return;
    CVPixelBufferRef dst=CMSampleBufferGetImageBuffer(sample);if(!dst)return;
    OSType format=CVPixelBufferGetPixelFormatType(dst);
    if(format!=kCVPixelFormatType_420YpCbCr8BiPlanarFullRange && format!=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && format!=kCVPixelFormatType_32BGRA)return;
    size_t w=CVPixelBufferGetWidth(dst),h=CVPixelBufferGetHeight(dst);
    NSString *key=[NSString stringWithFormat:@"%zu:%zu:%u",w,h,(unsigned)format];
    if(!os_unfair_lock_trylock(&_lock))return; // worker busy: leave real frame untouched
    CVPixelBufferRef src=NULL;
    @try {
    _lastCamera=CACurrentMediaTime();
    LMCCanvas *canvas=_canvases[key];
    if(!canvas && _enabled && w>0 && h>0 && w<=8192 && h<=8192 && w*h<=24*1024*1024){
        canvas=[LMCCanvas new];canvas->width=w;canvas->height=h;canvas->format=format;
        if(_canvases.count>=3)[_canvases removeObjectForKey:_canvases.allKeys.firstObject];
        _canvases[key]=canvas;
    }
    src=(_enabled&&canvas&&canvas->cached)?CVPixelBufferRetain(canvas->cached):NULL;
    } @finally {os_unfair_lock_unlock(&_lock);}
    if(!src)return;
    @try {if(LMCCopyPixels(src,dst))__atomic_fetch_add(&gReplaced,1,__ATOMIC_RELAXED);}
    @finally {CVPixelBufferRelease(src);}
}
@end

typedef void (*Render2IMP)(id,SEL,CMSampleBufferRef,id);
typedef void (*EmitIMP)(id,SEL,CMSampleBufferRef);
static Render2IMP origImageQueue,origPhotoEncoder,origRemoteQueue,origStillSink;
static EmitIMP origNodeOutput;
static void LMCSafeRender(CMSampleBufferRef s){@try{[[LMCFrameProvider shared] renderIntoSampleBuffer:s];}@catch(__unused NSException *e){}}
static void renderImageQueue(id o,SEL c,CMSampleBufferRef s,id in){LMCSafeRender(s);origImageQueue(o,c,s,in);}
static void renderPhoto(id o,SEL c,CMSampleBufferRef s,id in){LMCSafeRender(s);origPhotoEncoder(o,c,s,in);}
static void renderRemote(id o,SEL c,CMSampleBufferRef s,id in){LMCSafeRender(s);origRemoteQueue(o,c,s,in);}
static void renderStill(id o,SEL c,CMSampleBufferRef s,id in){LMCSafeRender(s);origStillSink(o,c,s,in);}
static void emitNode(id o,SEL c,CMSampleBufferRef s){LMCSafeRender(s);origNodeOutput(o,c,s);}
static void Hook(NSString *name,SEL selector,IMP replacement,IMP *original){
    if(*original)return;Class cls=NSClassFromString(name);if(!cls)return;
    Method method=class_getInstanceMethod(cls,selector);if(!method)return;
    // Skip an unexpected ABI rather than guessing private signatures.
    unsigned expected=sel_isEqual(selector,@selector(emitSampleBuffer:))?3:4;
    if(method_getNumberOfArguments(method)!=expected)return;
    char result[16];method_getReturnType(method,result,sizeof(result));if(strcmp(result,"v"))return;
    char sampleType[128];method_getArgumentType(method,2,sampleType,sizeof(sampleType));
    if(sampleType[0]!='^')return;
    MSHookMessageEx(cls,selector,replacement,original);
    if(*original){__atomic_fetch_add(&gHooks,1,__ATOMIC_RELAXED);NSLog(@"[iCamV3] hook %@ %@",name,NSStringFromSelector(selector));}
}
static void InstallHooks(void){
    Hook(@"BWNodeOutput",@selector(emitSampleBuffer:),(IMP)emitNode,(IMP *)&origNodeOutput);
    Hook(@"BWImageQueueSinkNode",@selector(renderSampleBuffer:forInput:),(IMP)renderImageQueue,(IMP *)&origImageQueue);
    Hook(@"BWPhotoEncoderNode",@selector(renderSampleBuffer:forInput:),(IMP)renderPhoto,(IMP *)&origPhotoEncoder);
    Hook(@"BWRemoteQueueSinkNode",@selector(renderSampleBuffer:forInput:),(IMP)renderRemote,(IMP *)&origRemoteQueue);
    Hook(@"BWStillImageSampleBufferSinkNode",@selector(renderSampleBuffer:forInput:),(IMP)renderStill,(IMP *)&origStillSink);
}
static void configChanged(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef info){[[LMCFrameProvider shared] reload];}
__attribute__((constructor))static void initiCamV3(void){@autoreleasepool{
    [[LMCFrameProvider shared] reload];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,configChanged,(__bridge CFStringRef)LMCConfigChangedNotification,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    InstallHooks();
    // Camera classes may be loaded AFTER the dylib constructor. Retry idempotently.
    static dispatch_source_t retry;retry=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(retry,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),2*NSEC_PER_SEC,NSEC_PER_SEC/10);
    dispatch_source_set_event_handler(retry,^{@autoreleasepool{InstallHooks();if(__atomic_load_n(&gHooks,__ATOMIC_RELAXED)==5){dispatch_source_cancel(retry);}}});
    dispatch_resume(retry);
}}
