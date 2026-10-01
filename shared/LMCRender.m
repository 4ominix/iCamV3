#import "LMCRender.h"
#import "LMCGeometry.h"
CIImage *LMCComposeImage(CIImage *image, CGSize size, LMCConfig *config) {
    CGRect e=image.extent;
    if (!image || CGRectIsEmpty(e) || CGRectIsInfinite(e)) return nil;
    image=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(-e.origin.x,-e.origin.y)];
    LMCMatrix m=LMCGeometry(e.size.width,e.size.height,size.width,size.height,(int)config.rotation,
       config.mirror,config.contentMode==LMCContentModeFill,config.zoom,config.offsetX,config.offsetY);
    if (!m.valid) return nil;
    image=[image imageByApplyingTransform:CGAffineTransformMake(m.a,m.b,m.c,m.d,m.tx,m.ty)];
    CGRect bounds=CGRectMake(0,0,size.width,size.height);
    CIImage *black=[[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:1]] imageByCroppingToRect:bounds];
    return [[image imageByCompositingOverImage:black] imageByCroppingToRect:bounds];
}
