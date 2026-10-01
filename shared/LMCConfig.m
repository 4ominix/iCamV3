#import "LMCConfig.h"
#import <CoreFoundation/CoreFoundation.h>
#import <roothide.h>
#import <sys/stat.h>
#import <math.h>

NSString * const LMCConfigChangedNotification = @"com.icamv3.config-changed";
static double Number(NSDictionary *d, NSString *key, double fallback) {
    id n=d[key]; double v=[n isKindOfClass:NSNumber.class] ? [n doubleValue] : fallback;
    return isfinite(v) ? v : fallback;
}
@implementation LMCConfig
// Native Foundation APIs need a physical jbroot path. Bootstrap shell tools do not.
+ (NSString *)baseDirectory { return jbroot(@"/var/mobile/Library/iCamV3"); }
+ (NSString *)preferencesPath { return [self.baseDirectory stringByAppendingPathComponent:@"Config.plist"]; }
- (NSString *)resolvedMediaPath {
    // Keep only a managed filename in the plist, so re-jailbreaking can change jbroot safely.
    NSString *name=self.mediaPath.lastPathComponent;
    if (![name hasPrefix:@"source."] || [name containsString:@"/"]) return @"";
    return [LMCConfig.baseDirectory stringByAppendingPathComponent:name];
}
+ (instancetype)load {
    LMCConfig *c=[LMCConfig new];
    NSDictionary *d=[NSDictionary dictionaryWithContentsOfFile:self.preferencesPath] ?: @{};
    c.enabled=Number(d,@"Enabled",0)!=0; c.loop=Number(d,@"Loop",1)!=0;
    c.mirror=Number(d,@"Mirror",0)!=0;
    double rotation=fmod(Number(d,@"Rotation",0),360.0);
    c.rotation=(((NSInteger)rotation+360)%360)/90*90;
    c.contentMode=Number(d,@"ContentMode",0)==1 ? LMCContentModeFill : LMCContentModeFit;
    c.zoom=fmax(0.25,fmin(8,Number(d,@"Zoom",1)));
    c.offsetX=fmax(-2,fmin(2,Number(d,@"OffsetX",0)));
    c.offsetY=fmax(-2,fmin(2,Number(d,@"OffsetY",0)));
    c.mediaPath=[d[@"MediaPath"] isKindOfClass:NSString.class] ? d[@"MediaPath"] : @"";
    c.mediaType=[d[@"MediaType"] isKindOfClass:NSString.class] ? d[@"MediaType"] : @"";
    return c;
}
- (BOOL)save:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:LMCConfig.baseDirectory withIntermediateDirectories:YES
          attributes:@{NSFilePosixPermissions:@0755} error:error]) return NO;
    NSDictionary *d=@{@"Enabled":@(self.enabled),@"Loop":@(self.loop),@"Mirror":@(self.mirror),
       @"Rotation":@(self.rotation),@"ContentMode":@(self.contentMode),@"Zoom":@(self.zoom),
       @"OffsetX":@(self.offsetX),@"OffsetY":@(self.offsetY),
       @"MediaPath":self.mediaPath.lastPathComponent ?: @"",@"MediaType":self.mediaType ?: @""};
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToFile:LMCConfig.preferencesPath options:NSDataWritingAtomic error:error]) return NO;
    chmod(LMCConfig.preferencesPath.fileSystemRepresentation,0644);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
       (__bridge CFStringRef)LMCConfigChangedNotification,NULL,NULL,true);
    return YES;
}
@end
