#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kDomain = @"com.cannon.nougat";
static NSString *const kOpenDrawerNote = @"com.cannon.openDrawer";

static BOOL cn_getBool(NSString *key) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain));
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

static void cn_setBool(NSString *key, BOOL val) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, val ? kCFBooleanTrue : kCFBooleanFalse, (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
}

@interface SBDockView : UIView
- (void)setBackgroundAlpha:(double)a;
@end

@interface SBDockIconListView : UIView
- (NSArray *)icons;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
@end

// 1) Seffaf dock + 2) 4. slotta cekmece dugmesi
%hook SBDockView
- (void)setBackgroundAlpha:(double)a {
    %orig(0.0);
}

- (void)layoutSubviews {
    %orig;
    UIButton *b = (UIButton *)[self viewWithTag:0xCA77];
    if (!cn_getBool(@"enabled")) {
        [b removeFromSuperview];
        return;
    }
    if (!b) {
        b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = 0xCA77;
        [b setImage:[UIImage systemImageNamed:@"circle.grid.3x3.fill"] forState:UIControlStateNormal];
        b.tintColor = UIColor.whiteColor;
        [b addTarget:self action:@selector(cn_openDrawer) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }
    CGFloat slot = self.bounds.size.width / 4.0;
    b.frame = CGRectMake(slot * 3, 0, slot, self.bounds.size.height);
}

%new
- (void)cn_openDrawer {
    // Cannon'un cekmece acma metodu bilinince buradan dogrudan cagrilacak
    [[NSNotificationCenter defaultCenter] postNotificationName:kOpenDrawerNote object:nil];
}
%end

// 3) Dock'ta en fazla 3 uygulama
%hook SBDockIconListView
- (BOOL)allowsAddingIconCount:(unsigned long long)n {
    if (!cn_getBool(@"enabled")) return %orig;
    return [[self icons] count] + n <= 3;
}
%end

// Uyari: ilk acilista bir kez gosterilir
static void cn_showWarning(void) {
    UIViewController *vc = [%c(SBIconController) sharedInstance];
    if (!vc) { // ekran hazir degil, tekrar dene
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ cn_showWarning(); });
        return;
    }
    while (vc.presentedViewController) vc = vc.presentedViewController;

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Uygulama çekmecesi"
        message:@"Dock'un 4. yuvası çekmece düğmesine ayrılacak. Dock'ta en fazla 3 uygulama kalacak. Dock'ta şu an 4 ikon varsa, devam etmeden önce birini dock'tan çıkar. Devam dersen SpringBoard yeniden başlatılacak."
        preferredStyle:UIAlertControllerStyleAlert];

    [a addAction:[UIAlertAction actionWithTitle:@"İptal" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        cn_setBool(@"warned", YES);
        cn_setBool(@"enabled", NO);
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Devam" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        cn_setBool(@"warned", YES);
        cn_setBool(@"enabled", YES);
        exit(0); // SpringBoard yeniden baslar
    }]];
    [vc presentViewController:a animated:YES completion:nil];
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)app {
    %orig;
    if (cn_getBool(@"warned")) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ cn_showWarning(); });
}
%end
