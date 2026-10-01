#ifndef LMC_GEOMETRY_H
#define LMC_GEOMETRY_H
#include <math.h>
typedef struct { double a,b,c,d,tx,ty; int valid; } LMCMatrix;
// Core Image coordinates: positive X right, positive Y up. Offsets are viewport fractions.
static inline LMCMatrix LMCGeometry(double sw,double sh,double dw,double dh,int rotation,
                                    int mirror,int fill,double zoom,double ox,double oy) {
    LMCMatrix m={0,0,0,0,0,0,0};
    if (!isfinite(sw)||!isfinite(sh)||!isfinite(dw)||!isfinite(dh)||
        sw<=0||sh<=0||dw<=0||dh<=0||!isfinite(zoom)||!isfinite(ox)||!isfinite(oy)) return m;
    int r=((rotation%360)+360)%360;
    double a=1,b=0,c=0,d=1;
    if(r==90){a=0;b=-1;c=1;d=0;} else if(r==180){a=-1;d=-1;}
    else if(r==270){a=0;b=1;c=-1;d=0;}
    double rw=(r==90||r==270)?sh:sw, rh=(r==90||r==270)?sw:sh;
    double s=(fill?fmax(dw/rw,dh/rh):fmin(dw/rw,dh/rh))*fmax(.25,fmin(8,zoom));
    if(mirror){a=-a;c=-c;}
    m.a=a*s;m.b=b*s;m.c=c*s;m.d=d*s;
    m.tx=dw*.5+fmax(-2,fmin(2,ox))*dw-(m.a*sw*.5+m.c*sh*.5);
    m.ty=dh*.5-fmax(-2,fmin(2,oy))*dh-(m.b*sw*.5+m.d*sh*.5);
    m.valid=1;return m;
}
#endif
