#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LMCContentMode) { LMCContentModeFit = 0, LMCContentModeFill = 1 };

@interface LMCConfig : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL loop;
@property(nonatomic) BOOL mirror;
@property(nonatomic) NSInteger rotation;
@property(nonatomic) LMCContentMode contentMode;
@property(nonatomic) double zoom;
@property(nonatomic) double offsetX;
@property(nonatomic) double offsetY;
@property(nonatomic, copy) NSString *mediaPath;
@property(nonatomic, copy) NSString *mediaType;
+ (NSString *)baseDirectory;
+ (NSString *)preferencesPath;
- (NSString *)resolvedMediaPath;
+ (instancetype)load;
- (BOOL)save:(NSError **)error;
@end

FOUNDATION_EXPORT NSString * const LMCConfigChangedNotification;
