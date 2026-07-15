#import <UIKit/UIKit.h>
#import <mach/mach_time.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef double   IOHIDFloat;
typedef uint32_t IOOptionBits;

#define kIOHIDDigitizerTransducerTypeHand 1

enum {
    kIOHIDDigitizerEventRange    = 0x00000001,
    kIOHIDDigitizerEventTouch    = 0x00000002,
    kIOHIDDigitizerEventIdentity = 0x00000020,
};

extern "C" {
    IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef a, uint64_t ts, uint32_t type, uint32_t idx, uint32_t ident, uint32_t mask, uint32_t btn, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat p, IOHIDFloat tw, Boolean rng, Boolean tch, IOOptionBits o);
    IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef a, uint64_t ts, uint32_t idx, uint32_t ident, uint32_t mask, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat p, IOHIDFloat tw, Boolean rng, Boolean tch, IOOptionBits o);
    void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, IOOptionBits o);
}

@interface UIApplication (Priv)
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
@end

static void SAC_post(CGPoint p, uint32_t mask, Boolean rng, Boolean tch) {
    CGSize sz = [UIScreen mainScreen].bounds.size;
    if (sz.width <= 0 || sz.height <= 0) return;
    uint64_t t = mach_absolute_time();
    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, t, kIOHIDDigitizerTransducerTypeHand, 0, 0, mask, 0, 0, 0, 0, 0, 0, rng, tch, 0);
    if (!parent) return;
    IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, t, 1, 2, mask, p.x/sz.width, p.y/sz.height, 0, 0, 0, rng, tch, 0);
    if (child) { IOHIDEventAppendEvent(parent, child, 0); CFRelease(child); }
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_enqueueHIDEvent:)]) [app _enqueueHIDEvent:parent];
    CFRelease(parent);
}

static void SAC_up(CGPoint p) { SAC_post(p, kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch, false, false); }

static void SAC_tap(CGPoint p) {
    SAC_post(p, kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity, true, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SAC_up(p); });
}

@interface SAC_Catcher : UIWindow
@property (nonatomic, copy) void (^onPick)(CGPoint);
@end
@implementation SAC_Catcher
- (void)handleTap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:nil];
    if (self.onPick) self.onPick(p);
    self.hidden = YES;
}
@end

// Small always-visible toggle button
@interface SAC_Toggle : UIWindow
@property (nonatomic, copy) void (^onTap)(void);
@end
@implementation SAC_Toggle
- (instancetype)initWithScene:(UIWindowScene *)scene {
    self = [super initWithFrame:CGRectMake(8, 120, 52, 52)];
    if (!self) return self;
    if (scene) self.windowScene = scene;
    self.windowLevel = UIWindowLevelAlert + 1500;
    self.backgroundColor = [UIColor clearColor];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = self.bounds;
    b.backgroundColor = [UIColor colorWithRed:0.15 green:0.5 blue:0.85 alpha:0.92];
    b.layer.cornerRadius = 26;
    [b setTitle:@"AC" forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    self.hidden = NO;
    return self;
}
- (void)tapped { if (self.onTap) self.onTap(); }
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    CGRect f = self.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    self.frame = f;
    [g setTranslation:CGPointZero inView:self];
}
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)e {
    return CGRectContainsPoint(self.bounds, pt) ? [super hitTest:pt withEvent:e] : nil;
}
@end

@interface SAC_Panel : UIWindow
@property (nonatomic, strong) UIView   *card;
@property (nonatomic, strong) UILabel  *targetLabel;
@property (nonatomic, strong) UILabel  *rateLabel;
@property (nonatomic, strong) UIButton *startBtn;
@property (nonatomic, strong) NSTimer  *timer;
@property (nonatomic, assign) CGPoint   target;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, assign) BOOL      running;
@property (nonatomic, strong) SAC_Catcher *catcher;
- (void)toggleVisible;
@end
@implementation SAC_Panel
- (instancetype)initWithScene:(UIWindowScene *)scene {
    self = [super initWithFrame:CGRectMake(70, 120, 210, 176)];
    if (!self) return self;
    if (scene) self.windowScene = scene;
    self.windowLevel = UIWindowLevelAlert + 1000;
    self.backgroundColor = [UIColor clearColor];
    self.interval = 0.10;
    self.target = CGPointMake(200, 200);
    self.card = [[UIView alloc] initWithFrame:self.bounds];
    self.card.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.92];
    self.card.layer.cornerRadius = 14;
    [self addSubview:self.card];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 210, 26)];
    title.text = @"AutoClicker  drag";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textColor = [UIColor whiteColor];
    title.userInteractionEnabled = YES;
    [title addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [self.card addSubview:title];
    self.targetLabel = [self mkLabel:CGRectMake(10, 30, 190, 18)];
    self.rateLabel = [self mkLabel:CGRectMake(10, 84, 190, 18)];
    [self refresh];
    [self.card addSubview:[self mkBtn:@"Set Target" frame:CGRectMake(10, 52, 190, 28) action:@selector(pickTarget)]];
    [self.card addSubview:[self mkBtn:@"-" frame:CGRectMake(10, 106, 40, 30) action:@selector(rateDown)]];
    [self.card addSubview:[self mkBtn:@"+" frame:CGRectMake(160, 106, 40, 30) action:@selector(rateUp)]];
    self.startBtn = [self mkBtn:@"START" frame:CGRectMake(10, 142, 190, 30) action:@selector(toggle)];
    self.startBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:1];
    [self.card addSubview:self.startBtn];
    self.hidden = YES;   // hidden until the AC button is tapped
    return self;
}
- (UILabel *)mkLabel:(CGRect)f {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    l.textAlignment = NSTextAlignmentCenter;
    [self.card addSubview:l];
    return l;
}
- (UIButton *)mkBtn:(NSString *)t frame:(CGRect)f action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    b.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    b.layer.cornerRadius = 8;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)refresh {
    self.targetLabel.text = [NSString stringWithFormat:@"Target: %.0f, %.0f", self.target.x, self.target.y];
    self.rateLabel.text = [NSString stringWithFormat:@"Interval: %.0f ms", self.interval * 1000.0];
}
- (void)toggleVisible { self.hidden = !self.hidden; }
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:pt withEvent:e];
    return (v == self) ? nil : v;
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    CGRect f = self.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    self.frame = f;
    [g setTranslation:CGPointZero inView:self];
}
- (void)rateDown { self.interval = MIN(1.0, self.interval + 0.01); [self refresh]; [self restart]; }
- (void)rateUp   { self.interval = MAX(0.02, self.interval - 0.01); [self refresh]; [self restart]; }
- (void)pickTarget {
    if (!self.catcher) {
        self.catcher = [[SAC_Catcher alloc] initWithFrame:[UIScreen mainScreen].bounds];
        if (self.windowScene) self.catcher.windowScene = self.windowScene;
        self.catcher.windowLevel = UIWindowLevelAlert + 2000;
        self.catcher.backgroundColor = [UIColor colorWithWhite:0 alpha:0.15];
        [self.catcher addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self.catcher action:@selector(handleTap:)]];
        __weak typeof(self) ws = self;
        self.catcher.onPick = ^(CGPoint p){ ws.target = p; [ws refresh]; };
    }
    self.catcher.hidden = NO;
}
- (void)toggle { if (self.running) [self stop]; else [self start]; }
- (void)start {
    self.running = YES;
    [self.startBtn setTitle:@"STOP" forState:UIControlStateNormal];
    self.startBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:1];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval target:self selector:@selector(fire) userInfo:nil repeats:YES];
}
- (void)stop {
    self.running = NO;
    [self.startBtn setTitle:@"START" forState:UIControlStateNormal];
    self.startBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:1];
    [self.timer invalidate];
    self.timer = nil;
}
- (void)restart { if (self.running) { [self stop]; [self start]; } }
- (void)fire { SAC_tap(self.target); }
@end

static SAC_Panel  *gPanel  = nil;
static SAC_Toggle *gToggle = nil;
static void SAC_spawn(void) {
    if (gToggle) return;
    UIWindowScene *active = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) { active = (UIWindowScene *)scene; break; }
    }
    if (!active) return;
    gPanel  = [[SAC_Panel alloc] initWithScene:active];
    gToggle = [[SAC_Toggle alloc] initWithScene:active];
    gToggle.onTap = ^{ if (gPanel) [gPanel toggleVisible]; };
}

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if ([bid isEqualToString:@"com.apple.springboard"]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SAC_spawn(); });
}
