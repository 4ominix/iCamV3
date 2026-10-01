#import "LMCControlPanel.h"
#import <math.h>
@interface LMCControlPanel ()
@property(nonatomic,strong) UILabel *zoomLabel;
@end
@implementation LMCControlPanel
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=[UIColor colorWithWhite:.07 alpha:.97]; self.layer.cornerRadius=18;
        UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;
        stack.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
          [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
          [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
          [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14]]];
        UILabel *title=[UILabel new];title.text=@"Camera control";title.textColor=UIColor.whiteColor;
        title.font=[UIFont boldSystemFontOfSize:18];title.textAlignment=NSTextAlignmentCenter;[stack addArrangedSubview:title];
        [stack addArrangedSubview:[self row:@[@"↑"] tags:@[@1]]];
        [stack addArrangedSubview:[self row:@[@"←",@"↻",@"→"] tags:@[@2,@3,@4]]];
        [stack addArrangedSubview:[self row:@[@"↓"] tags:@[@5]]];
        UIStackView *zoom=[self row:@[@"−",@"+"] tags:@[@6,@7]];
        self.zoomLabel=[UILabel new];self.zoomLabel.textColor=UIColor.whiteColor;
        self.zoomLabel.textAlignment=NSTextAlignmentCenter;[zoom insertArrangedSubview:self.zoomLabel atIndex:1];
        [stack addArrangedSubview:zoom];
        [stack addArrangedSubview:[self row:@[@"⇆",@"Đặt lại"] tags:@[@8,@9]]];[self refresh];
    } return self;
}
- (UIStackView *)row:(NSArray<NSString *> *)titles tags:(NSArray<NSNumber *> *)tags {
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;
    row.distribution=UIStackViewDistributionFillEqually;row.spacing=12;
    [titles enumerateObjectsUsingBlock:^(NSString *s,NSUInteger i,BOOL *stop){
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.tag=[tags[i] integerValue];
        [b setTitle:s forState:UIControlStateNormal];[b setTitleColor:UIColor.systemTealColor forState:UIControlStateNormal];
        b.titleLabel.font=[UIFont boldSystemFontOfSize:25];b.backgroundColor=[UIColor colorWithWhite:.16 alpha:1];
        b.layer.cornerRadius=24;[b.heightAnchor constraintEqualToConstant:48].active=YES;
        [b addTarget:self action:@selector(pressed:) forControlEvents:UIControlEventTouchUpInside];[row addArrangedSubview:b];
    }];return row;
}
- (void)refresh { self.zoomLabel.text=[NSString stringWithFormat:@"%.2fx",[LMCConfig load].zoom]; }
- (void)pressed:(UIButton *)button {
    // Read newest config on every action; floating controls never overwrite a new media selection.
    LMCConfig *c=[LMCConfig load];
    switch(button.tag){case 1:c.offsetY-=.025;break;case 2:c.offsetX-=.025;break;
       case 3:c.rotation=(c.rotation+90)%360;break;case 4:c.offsetX+=.025;break;
       case 5:c.offsetY+=.025;break;case 6:c.zoom/=1.1;break;case 7:c.zoom*=1.1;break;
       case 8:c.mirror=!c.mirror;break;case 9:c.offsetX=0;c.offsetY=0;c.zoom=1;c.rotation=0;c.mirror=NO;break;}
    c.zoom=fmax(.25,fmin(8,c.zoom));c.offsetX=fmax(-2,fmin(2,c.offsetX));c.offsetY=fmax(-2,fmin(2,c.offsetY));
    NSError *e=nil;BOOL ok=[c save:&e];[self refresh];
    if(self.configurationChanged)self.configurationChanged(ok?c:[LMCConfig load],e);
}
@end
