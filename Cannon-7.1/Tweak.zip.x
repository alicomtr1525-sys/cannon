#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kDomain = @"com.cannon.nougat";
static const CGFloat kDockScale = 0.82; // dock ikon boyutu (1.0 = normal)

static BOOL cn_getBool(NSString *key) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain));
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

static void cn_setBool(NSString *key, BOOL val) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, val ? kCFBooleanTrue : kCFBooleanFalse, (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
}

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
- (NSArray *)appTags;
- (NSString *)applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bid;
@end

@interface UIImage (CNPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)fmt scale:(double)scale;
@end

@interface SBDockView : UIView
- (void)setBackgroundAlpha:(double)a;
@end

@interface SBDockIconListView : UIView
- (NSArray *)icons;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
@end

// ---------- Uygulama acma ----------
static void cn_launch(NSString *bid) {
    Class c = objc_getClass("FBSSystemService");
    SEL shared = NSSelectorFromString(@"sharedService");
    id svc = (c && [c respondsToSelector:shared]) ? ((id (*)(id, SEL))objc_msgSend)(c, shared) : nil;
    SEL open = NSSelectorFromString(@"openApplication:options:withResult:");
    if (svc && [svc respondsToSelector:open]) {
        void (^done)(NSError *) = ^(NSError *e) {};
        ((void (*)(id, SEL, NSString *, NSDictionary *, id))objc_msgSend)(svc, open, bid, @{}, done);
        return;
    }
    [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:bid];
}

// ---------- Cekmece hucresi ----------
@interface CNCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@end

@implementation CNCell
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    _icon = [[UIImageView alloc] init];
    _icon.clipsToBounds = YES;
    _icon.contentMode = UIViewContentModeScaleAspectFill;
    _label = [[UILabel alloc] init];
    _label.font = [UIFont systemFontOfSize:11];
    _label.textColor = [UIColor colorWithWhite:0.25 alpha:1];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.numberOfLines = 1;
    [self.contentView addSubview:_icon];
    [self.contentView addSubview:_label];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, s = 54;
    _icon.frame = CGRectMake((w - s) / 2, 6, s, s);
    _icon.layer.cornerRadius = s / 2; // yuvarlak ikon
    _label.frame = CGRectMake(2, 64, w - 4, 16);
}
@end

// ---------- Cekmece ----------
@interface CNDrawerView : UIView <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) NSArray<NSDictionary *> *apps;
@property (nonatomic, strong) NSCache *cache;
+ (instancetype)shared;
- (void)showInHost:(UIView *)host;
- (void)hide;
@end

@implementation CNDrawerView
+ (instancetype)shared {
    static CNDrawerView *v;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ v = [[CNDrawerView alloc] initWithFrame:CGRectZero]; });
    return v;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.97];
    _cache = [[NSCache alloc] init];

    _closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_closeBtn setImage:[UIImage systemImageNamed:@"chevron.compact.down"] forState:UIControlStateNormal];
    _closeBtn.tintColor = [UIColor colorWithWhite:0.4 alpha:1];
    [_closeBtn addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_closeBtn];

    UICollectionViewFlowLayout *l = [[UICollectionViewFlowLayout alloc] init];
    l.minimumInteritemSpacing = 0;
    l.minimumLineSpacing = 6;
    _grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:l];
    _grid.backgroundColor = UIColor.clearColor;
    _grid.dataSource = self;
    _grid.delegate = self;
    [_grid registerClass:[CNCell class] forCellWithReuseIdentifier:@"c"];
    [self addSubview:_grid];

    UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedDown)];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    down.delegate = self;
    [self addGestureRecognizer:down];
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

- (void)swipedDown {
    if (self.grid.contentOffset.y <= 1) [self hide];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _closeBtn.frame = CGRectMake(w / 2 - 30, 22, 60, 32);
    _grid.frame = CGRectMake(0, 60, w, h - 60);
}

- (void)reload {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (LSApplicationProxy *p in [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications]) {
        NSString *bid = [p respondsToSelector:@selector(applicationIdentifier)] ? [p applicationIdentifier] : nil;
        NSString *name = [p respondsToSelector:@selector(localizedName)] ? [p localizedName] : nil;
        NSArray *tags = [p respondsToSelector:@selector(appTags)] ? [p appTags] : nil;
        NSString *type = [p respondsToSelector:@selector(applicationType)] ? [p applicationType] : nil;
        if (!bid.length || !name.length || [seen containsObject:bid]) continue;
        if ([tags containsObject:@"hidden"]) continue;
        if (type && !([type isEqualToString:@"User"] || [type isEqualToString:@"System"])) continue;
        [seen addObject:bid];
        [out addObject:@{ @"bid": bid, @"name": name }];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    self.apps = out;
    [self.grid reloadData];
    self.grid.contentOffset = CGPointZero;
}

- (void)showInHost:(UIView *)host {
    if (self.superview) return;
    [self reload];
    self.frame = host.bounds;
    self.transform = CGAffineTransformMakeTranslation(0, host.bounds.size.height);
    [host addSubview:self];
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hide {
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height);
    } completion:^(BOOL f) {
        [self removeFromSuperview];
        self.transform = CGAffineTransformIdentity;
    }];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.apps.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CNCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    NSDictionary *a = self.apps[ip.item];
    UIImage *img = [self.cache objectForKey:a[@"bid"]];
    if (!img) {
        img = [UIImage _applicationIconImageForBundleIdentifier:a[@"bid"] format:10 scale:UIScreen.mainScreen.scale];
        if (img) [self.cache setObject:img forKey:a[@"bid"]];
    }
    c.icon.image = img;
    c.label.text = a[@"name"];
    return c;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    return CGSizeMake(floor(cv.bounds.size.width / 4.0), 88);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSString *bid = self.apps[ip.item][@"bid"];
    [self hide];
    cn_launch(bid);
}
@end

static void cn_openDrawer(void) {
    UIViewController *vc = [%c(SBIconController) sharedInstance];
    UIView *host = vc.view.window;
    if (host) [[CNDrawerView shared] showInHost:host];
}

// ---------- Dock ----------
%hook SBDockView
- (void)setBackgroundAlpha:(double)a {
    %orig(0.0); // seffaf dock
}

- (void)layoutSubviews {
    %orig;
    static char key;
    if (!objc_getAssociatedObject(self, &key)) {
        UISwipeGestureRecognizer *g = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(cn_swipedUp)];
        g.direction = UISwipeGestureRecognizerDirectionUp;
        [self addGestureRecognizer:g];
        objc_setAssociatedObject(self, &key, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%new
- (void)cn_swipedUp {
    if (cn_getBool(@"enabled")) cn_openDrawer();
}
%end

%hook SBDockIconListView
- (BOOL)allowsAddingIconCount:(unsigned long long)n {
    if (!cn_getBool(@"enabled")) return %orig;
    return [[self icons] count] + n <= 4;
}

- (void)layoutSubviews {
    %orig;
    UIButton *b = (UIButton *)[self viewWithTag:0xCA77];
    if (!cn_getBool(@"enabled")) {
        [b removeFromSuperview];
        return;
    }
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat slot = w / 5.0;

    // ikonlari 5 yuvaya diz: 0,1,(orta=cekmece),3,4
    NSMutableArray *views = [NSMutableArray array];
    Class iv = objc_getClass("SBIconView");
    for (UIView *s in self.subviews) {
        if (iv && [s isKindOfClass:iv]) [views addObject:s];
    }
    [views sortUsingComparator:^NSComparisonResult(UIView *a, UIView *c) {
        return a.center.x < c.center.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    static const int slots[4] = { 0, 1, 3, 4 };
    for (NSUInteger i = 0; i < views.count && i < 4; i++) {
        UIView *v = views[i];
        v.center = CGPointMake(slot * (slots[i] + 0.5), v.center.y);
        v.transform = CGAffineTransformMakeScale(kDockScale, kDockScale);
    }

    if (!b) {
        b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = 0xCA77;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:26];
        [b setImage:[UIImage systemImageNamed:@"circle.grid.3x3.fill" withConfiguration:cfg] forState:UIControlStateNormal];
        b.tintColor = UIColor.whiteColor;
        [b addTarget:self action:@selector(cn_openDrawerTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }
    b.frame = CGRectMake(slot * 2, 0, slot, h);
}

%new
- (void)cn_openDrawerTap {
    cn_openDrawer();
}
%end

// ---------- Uyari ----------
static void cn_showWarning(void) {
    UIViewController *vc = [%c(SBIconController) sharedInstance];
    if (!vc) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ cn_showWarning(); });
        return;
    }
    while (vc.presentedViewController) vc = vc.presentedViewController;

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Uygulama çekmecesi"
        message:@"Dock'un ortası çekmece düğmesi olacak. Dock'ta en fazla 4 uygulama kalacak ve ikonları küçülecek. Dock'ta 4'ten fazla ikon varsa fazlalıkları önce dock'tan çıkar. Dock'ta yukarı kaydırınca da çekmece açılır. Devam dersen SpringBoard yeniden başlatılacak."
        preferredStyle:UIAlertControllerStyleAlert];

    [a addAction:[UIAlertAction actionWithTitle:@"İptal" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        cn_setBool(@"warned2", YES);
        cn_setBool(@"enabled", NO);
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Devam" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        cn_setBool(@"warned2", YES);
        cn_setBool(@"enabled", YES);
        exit(0);
    }]];
    [vc presentViewController:a animated:YES completion:nil];
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)app {
    %orig;
    if (cn_getBool(@"warned2")) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ cn_showWarning(); });
}
%end
