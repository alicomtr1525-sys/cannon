#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "CNDrawerView.h"

// Alt kenardan başlayan kaydırma iPhone 7'de Control Center'a ait; çekmece jesti buradan başlamaz.
static const CGFloat kBottomExclusion = 50.0;
// Yukarı kaydırmanın tam açılış sayılacağı yüksekliğin oranı
static const CGFloat kTravelFraction = 0.9;

// SpringBoard özel sınıfları: iOS 15 başlıklarıyla ve cihazda doğrulanacak
@interface SBHomeScreenViewController : UIViewController
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isEditing;
@end

@interface SBDockView : UIView
@property (nonatomic, retain) UIView *backgroundView;
- (void)setBackgroundAlpha:(double)alpha;
@end

#pragma mark - Jest

@interface CNPanGestureRecognizer : UIPanGestureRecognizer
@property (nonatomic, assign) CGPoint startPoint;
@end

@implementation CNPanGestureRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch *t = touches.anyObject;
    if (t) self.startPoint = [t locationInView:self.view];
}
@end

static CNDrawerView *gDrawer;
static char kInstalledKey;

@interface CNGestureHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handlePan:(CNPanGestureRecognizer *)pan;
@end

@implementation CNGestureHandler

+ (instancetype)shared {
    static CNGestureHandler *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [[CNGestureHandler alloc] init]; });
    return h;
}

- (BOOL)homeScreenIsEditing {
    Class c = NSClassFromString(@"SBIconController");
    if (c && [(id)c respondsToSelector:@selector(sharedInstance)]) {
        SBIconController *ic = [(id)c sharedInstance];
        if ([ic respondsToSelector:@selector(isEditing)]) return [ic isEditing];
    }
    return NO;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    CNPanGestureRecognizer *pan = (CNPanGestureRecognizer *)g;
    if (gDrawer.isOpen) return NO;
    CGPoint v = [pan velocityInView:pan.view];
    if (!(v.y < 0 && fabs(v.y) > fabs(v.x) * 1.5)) return NO;           // belirgin şekilde yukarı
    if (pan.startPoint.y > pan.view.bounds.size.height - kBottomExclusion) return NO;  // Control Center bölgesi
    if ([self homeScreenIsEditing]) return NO;                           // ikon düzenleme modunda çalışmasın
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)ensureDrawerInHost:(UIView *)host {
    if (!gDrawer) gDrawer = [[CNDrawerView alloc] initWithFrame:host.bounds];
    if (gDrawer.superview != host) [host addSubview:gDrawer];
    gDrawer.frame = host.bounds;
    gDrawer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host bringSubviewToFront:gDrawer];
    [gDrawer layoutIfNeeded];
}

- (void)handlePan:(CNPanGestureRecognizer *)pan {
    UIView *host = pan.view;
    CGFloat H = MAX(host.bounds.size.height, 1.0);
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            [self ensureDrawerInHost:host];
            [gDrawer reloadApps];
            gDrawer.progress = 0;
            gDrawer.hidden = NO;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat dy = -[pan translationInView:host].y;
            gDrawer.progress = dy / (H * kTravelFraction);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            CGFloat vy = [pan velocityInView:host].y;
            BOOL open = (vy < -800.0) || (gDrawer.progress > 0.35 && vy < 300.0);
            [gDrawer settleOpen:open velocity:vy];
            break;
        }
        default: break;
    }
}

@end

#pragma mark - Hook

%hook SBHomeScreenViewController

- (void)viewDidLoad {
    %orig;
    UIView *host = self.view;
    if (!host || objc_getAssociatedObject(host, &kInstalledKey)) return;
    objc_setAssociatedObject(host, &kInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CNPanGestureRecognizer *pan = [[CNPanGestureRecognizer alloc] initWithTarget:[CNGestureHandler shared]
                                                                          action:@selector(handlePan:)];
    pan.delegate = [CNGestureHandler shared];
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = NO;
    [host addGestureRecognizer:pan];
    NSLog(@"[Cannon] jest eklendi: %@", host);
}

%end


#pragma mark - Dock arka planını kaldır
// SBDockView: _backgroundView, _backgroundImageView, _accessibilityBackgroundView ve setBackgroundAlpha:
// (iOS 15.7.3 başlıkları; 15.8.8'de cihazda doğrulanacak)

%hook SBDockView

- (void)setBackgroundAlpha:(double)alpha {
    %orig(0.0);
}

- (void)layoutSubviews {
    %orig;
    for (NSString *key in @[@"_backgroundView", @"_backgroundImageView", @"_accessibilityBackgroundView"]) {
        @try {
            UIView *v = [self valueForKey:key];
            if ([v isKindOfClass:[UIView class]]) v.hidden = YES;
        } @catch (NSException *e) { /* bu sürümde yoksa geç */ }
    }
}

%end

%ctor {
    NSLog(@"[Cannon] yüklendi, SBHomeScreenViewController=%@", NSClassFromString(@"SBHomeScreenViewController"));
}
