#include <assert.h>
#include <stdio.h>
#include "../shared/LMCGeometry.h"
static void near(double a,double b){assert(fabs(a-b)<1e-8);}
int main(void){
    LMCMatrix m=LMCGeometry(100,100,200,400,0,0,0,1,0,0);
    assert(m.valid);near(m.a,2);near(m.d,2);near(m.tx,0);near(m.ty,100);
    m=LMCGeometry(100,100,200,400,0,0,1,1,0,0);near(m.a,4);near(m.tx,-100);near(m.ty,0);
    m=LMCGeometry(100,200,400,200,90,0,0,1,0,0);near(m.a,0);near(m.b,-2);near(m.c,2);near(m.tx,0);near(m.ty,200);
    m=LMCGeometry(100,200,400,200,270,0,0,1,0,0);near(m.b,2);near(m.c,-2);near(m.tx,400);near(m.ty,0);
    m=LMCGeometry(100,100,100,100,180,0,0,1,0,0);near(m.a,-1);near(m.d,-1);near(m.tx,100);near(m.ty,100);
    m=LMCGeometry(100,100,100,100,0,1,0,1,.1,.2);near(m.a,-1);near(m.tx,110);near(m.ty,-20);
    m=LMCGeometry(100,100,100,100,0,0,0,2,0,0);near(m.a,2);near(m.tx,-50);
    m=LMCGeometry(0,100,100,100,0,0,0,1,0,0);assert(!m.valid);
    m=LMCGeometry(NAN,100,100,100,0,0,0,1,0,0);assert(!m.valid);
    m=LMCGeometry(100,100,100,100,0,0,0,INFINITY,0,0);assert(!m.valid);
    puts("PASS: geometry Fit/Fill, rotations, mirror, pan, zoom and invalid input");return 0;
}
