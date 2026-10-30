#import "CNDrawerView.h"
#import <objc/message.h>
#import <dlfcn.h>

// ---- Trebuchet (LineageOS lineage-20.0) kaynağından alınan değerler ----
// res/values/dimens.xml, res/xml/device_profiles.xml, res/layout/search_container_all_apps.xml
static const NSInteger kColumns = 4;          // küçük ızgaralarda çekmece sütunu
static const CGFloat kIconSize = 60.0;        // allAppsIconSize
static const CGFloat kLabelFontSize = 14.0;   // allAppsIconTextSize
static const CGFloat kCellHeight = 104.0;     // allAppsCellHeight
static const CGFloat kBorderSpace = 16.0;     // allAppsBorderSpace
static const CGFloat kSearchHeight = 48.0;    // arama alanı yüksekliği
static const CGFloat kSearchFontSize = 20.0;  // arama yazısı
// ---- Bizim tahminlerimiz / cihazda doğrulanacaklar ----
static const CGFloat kSideInset = 16.0;
static const CGFloat kSearchIconAreaWidth = 56.0; // büyüteç + yazıya kadar boşluk
static const CGFloat kSheetCornerRadius = 28.0;
static const int kIconFormat = 2;             // doğrula: iOS 15'te 60pt ana ekran ikonu için format

@interface UIImage (CNPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

#pragma mark - Hücre

@interface CNAppCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *label;
@end

@implementation CNAppCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_iconView];

        _label = [[UILabel alloc] init];
        _label.font = [UIFont systemFontOfSize:kLabelFontSize];
        _label.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 1;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_label];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat top = 9.0;
    self.iconView.frame = CGRectMake((w - kIconSize) / 2.0, top, kIconSize, kIconSize);
    self.label.frame = CGRectMake(2.0, top + kIconSize + 8.0, w - 4.0, 18.0);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.6 : 1.0;
}

@end

#pragma mark - Çekmece

@interface CNDrawerView () <UICollectionViewDataSource, UICollectionViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *scrim;
@property (nonatomic, strong) UIView *sheet;
@property (nonatomic, strong) UIView *searchPill;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIPanGestureRecognizer *dismissPan;
@property (nonatomic, copy) NSArray<NSDictionary *> *allApps;
@property (nonatomic, copy) NSArray<NSDictionary *> *shownApps;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property (nonatomic, assign) CGFloat keyboardHeight;
@property (nonatomic, assign) BOOL open;
@end

@implementation CNDrawerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _iconCache = [[NSCache alloc] init];
        _iconCache.countLimit = 120;
        _allApps = @[];
        _shownApps = @[];
        self.hidden = YES;

        _scrim = [[UIView alloc] init];
        _scrim.backgroundColor = [UIColor blackColor];
        _scrim.alpha = 0;
        [self addSubview:_scrim];
        [_scrim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scrimTapped)]];

        _sheet = [[UIView alloc] init];
        _sheet.backgroundColor = [UIColor colorWithRed:0.09 green:0.10 blue:0.10 alpha:0.97];
        _sheet.layer.cornerRadius = kSheetCornerRadius;
        _sheet.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        _sheet.clipsToBounds = YES;
        [self addSubview:_sheet];

        // Arama alanı: tam hap şekli (Trebuchet 200dp yarıçap), 48 yükseklik
        _searchPill = [[UIView alloc] init];
        _searchPill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        _searchPill.layer.cornerRadius = kSearchHeight / 2.0;
        _searchPill.clipsToBounds = YES;
        [_sheet addSubview:_searchPill];

        UIImageSymbolConfiguration *glassCfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
        UIImageView *glass = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:glassCfg]];
        glass.tintColor = [UIColor colorWithWhite:1.0 alpha:0.6];
        glass.contentMode = UIViewContentModeCenter; // ölçeklemeden ortala
        glass.frame = CGRectMake(0, 0, kSearchIconAreaWidth, kSearchHeight);

        _searchField = [[UITextField alloc] init];
        _searchField.leftView = glass;
        _searchField.leftViewMode = UITextFieldViewModeAlways;
        _searchField.textColor = [UIColor whiteColor];
        _searchField.font = [UIFont systemFontOfSize:kSearchFontSize];
        _searchField.tintColor = [UIColor whiteColor];
        _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
        _searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _searchField.returnKeyType = UIReturnKeySearch;
        _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _searchField.delegate = self;
        NSString *lang = [NSLocale preferredLanguages].firstObject ?: @"en";
        NSString *hint = [lang hasPrefix:@"tr"] ? @"Uygulama ara" : @"Search apps";
        _searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:hint attributes:@{
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.6],
            NSFontAttributeName: [UIFont systemFontOfSize:kSearchFontSize]
        }];
        [_searchField addTarget:self action:@selector(searchTextChanged) forControlEvents:UIControlEventEditingChanged];
        [_searchPill addSubview:_searchField];

        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.minimumInteritemSpacing = kBorderSpace;
        layout.minimumLineSpacing = 0;            // tahmin: satır aralığı hücre yüksekliğine dahil
        layout.sectionInset = UIEdgeInsetsMake(0, kSideInset, 16, kSideInset);
        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        _collectionView.alwaysBounceVertical = YES;
        _collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
        [_collectionView registerClass:[CNAppCell class] forCellWithReuseIdentifier:@"cell"];
        [_sheet addSubview:_collectionView];

        // Liste en üstteyken aşağı çekince kapat
        _dismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
        _dismissPan.delegate = self;
        [_sheet addGestureRecognizer:_dismissPan];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                     name:UIKeyboardWillChangeFrameNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isOpen { return self.open; }

#pragma mark Yerleşim

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    self.scrim.frame = self.bounds;
    // transform varken frame yerine bounds+center kullan
    self.sheet.bounds = CGRectMake(0, 0, W, H);
    self.sheet.center = CGPointMake(W / 2.0, H / 2.0);

    CGFloat safeTop = self.safeAreaInsets.top > 0 ? self.safeAreaInsets.top : 20.0;
    CGFloat y = safeTop + 16.0;
    self.searchPill.frame = CGRectMake(kSideInset, y, W - 2 * kSideInset, kSearchHeight);
    self.searchField.frame = self.searchPill.bounds;
    CGFloat listTop = CGRectGetMaxY(self.searchPill.frame) + 16.0;
    self.collectionView.frame = CGRectMake(0, listTop, W, H - listTop);

    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    CGFloat usable = W - 2 * kSideInset - (kColumns - 1) * kBorderSpace;
    CGFloat itemW = floor(usable / kColumns);
    if (itemW != layout.itemSize.width) {
        layout.itemSize = CGSizeMake(itemW, kCellHeight);
        [layout invalidateLayout];
    }
    [self applyProgress];
}

- (void)setProgress:(CGFloat)progress {
    _progress = MAX(0.0, MIN(1.0, progress));
    [self applyProgress];
}

- (void)applyProgress {
    CGFloat H = self.bounds.size.height;
    self.sheet.transform = CGAffineTransformMakeTranslation(0, (1.0 - _progress) * H);
    self.scrim.alpha = _progress * 0.45;
}

#pragma mark Açma / kapama

- (void)settleOpen:(BOOL)open velocity:(CGFloat)velocityY {
    self.hidden = NO;
    if (!open) [self.searchField resignFirstResponder];
    CGFloat H = MAX(self.bounds.size.height, 1.0);
    CGFloat remaining = open ? (1.0 - _progress) : _progress;
    CGFloat initialSpringVelocity = MIN(MAX(fabs(velocityY) / (remaining * H + 1.0), 0.0), 8.0);
    [UIView animateWithDuration:0.38 delay:0
         usingSpringWithDamping:0.92 initialSpringVelocity:initialSpringVelocity
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.progress = open ? 1.0 : 0.0; }
                     completion:^(BOOL finished) {
        self.open = open;
        if (!open) {
            self.hidden = YES;
            self.searchField.text = @"";
            [self applyFilter];
            [self.collectionView setContentOffset:CGPointZero animated:NO];
        }
    }];
}

- (void)scrimTapped { [self settleOpen:NO velocity:0]; }

- (void)handleDismissPan:(UIPanGestureRecognizer *)pan {
    CGFloat H = MAX(self.bounds.size.height, 1.0);
    switch (pan.state) {
        case UIGestureRecognizerStateChanged: {
            CGFloat ty = MAX(0, [pan translationInView:self].y);
            self.progress = 1.0 - ty / H;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat vy = [pan velocityInView:self].y;
            BOOL close = (vy > 800.0) || (self.progress < 0.65);
            [self settleOpen:!close velocity:vy];
            break;
        }
        default: break;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (g != self.dismissPan) return YES;
    CGPoint v = [self.dismissPan velocityInView:self];
    BOOL downward = v.y > 0 && fabs(v.y) > fabs(v.x) * 1.5;
    BOOL atTop = self.collectionView.contentOffset.y <= -self.collectionView.adjustedContentInset.top + 0.5;
    return downward && atTop && !self.searchField.isFirstResponder;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

#pragma mark Uygulama listesi

- (void)reloadApps {
    NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, NSSelectorFromString(@"defaultWorkspace"));
        SEL listSel = NSSelectorFromString(@"allInstalledApplications");
        if (![ws respondsToSelector:listSel]) listSel = NSSelectorFromString(@"allApplications");
        NSArray *proxies = ((id (*)(id, SEL))objc_msgSend)(ws, listSel);
        for (id p in proxies) {
            @try {
                NSString *bid = [p valueForKey:@"bundleIdentifier"];
                NSString *name = [p valueForKey:@"localizedName"];
                NSString *type = [p valueForKey:@"applicationType"];
                if (!bid.length || !name.length) continue;
                if (![type isEqualToString:@"User"] && ![type isEqualToString:@"System"]) continue;
                NSArray *tags = nil;
                if ([p respondsToSelector:NSSelectorFromString(@"appTags")]) tags = [p valueForKey:@"appTags"];
                if ([tags containsObject:@"hidden"]) continue;
                [list addObject:@{ @"bid": bid, @"name": name }];
            } @catch (NSException *e) { /* tek bir uygulama listeyi bozmasın */ }
        }
    } @catch (NSException *e) {
        NSLog(@"[Cannon] uygulama listesi okunamadı: %@", e);
    }
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
    self.allApps = list;
    [self applyFilter];
}

- (void)applyFilter {
    NSString *q = [self.searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (q.length == 0) {
        self.shownApps = self.allApps;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
            return [d[@"name"] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
        }];
        self.shownApps = [self.allApps filteredArrayUsingPredicate:pred];
    }
    [self.collectionView reloadData];
}

- (void)searchTextChanged { [self applyFilter]; }

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

#pragma mark Klavye

- (void)keyboardChanged:(NSNotification *)n {
    CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect inSelf = [self convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.bounds) - inSelf.origin.y);
    self.keyboardHeight = overlap;
    UIEdgeInsets inset = self.collectionView.contentInset;
    inset.bottom = overlap;
    self.collectionView.contentInset = inset;
    self.collectionView.scrollIndicatorInsets = inset;
}

#pragma mark Collection view

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.shownApps.count;
}

- (UIImage *)iconForBundleID:(NSString *)bid {
    UIImage *img = [self.iconCache objectForKey:bid];
    if (img) return img;
    CGFloat scale = [UIScreen mainScreen].scale;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        img = [UIImage _applicationIconImageForBundleIdentifier:bid format:kIconFormat scale:scale];
    }
    if (img) [self.iconCache setObject:img forKey:bid];
    return img;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    CNAppCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:ip];
    NSDictionary *app = self.shownApps[ip.item];
    cell.label.text = app[@"name"];
    cell.iconView.image = [self iconForBundleID:app[@"bid"]];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSString *bid = self.shownApps[ip.item][@"bid"];
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [self settleOpen:NO velocity:0];   // önce çekmeceyi kapat, arayüz hemen tepki versin
    // Açma isteğini ana thread dışında yap: SpringBoard kendi XPC cevabını ana thread'de işliyorsa
    // ana thread'den yapılan çağrı beklemeye girebilir (20 sn gecikme şüphesi, doğrulanmadı).
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL ok = NO;
        @try {
            Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
            id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, NSSelectorFromString(@"defaultWorkspace"));
            ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, NSSelectorFromString(@"openApplicationWithBundleID:"), bid);
        } @catch (NSException *e) {
            NSLog(@"[Cannon] LS açma hatası %@: %@", bid, e);
        }
        NSLog(@"[Cannon] LS openApplication %@ -> %d, %.2f sn", bid, ok, CFAbsoluteTimeGetCurrent() - t0);
        if (!ok) {
            // Yedek yol: SpringBoardServices (dlsym ile)
            void *h = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
            int (*launch)(CFStringRef, Boolean) = h ? (int (*)(CFStringRef, Boolean))dlsym(h, "SBSLaunchApplicationWithIdentifier") : NULL;
            if (launch) {
                int r = launch((__bridge CFStringRef)bid, false);
                NSLog(@"[Cannon] SBS launch %@ -> %d, %.2f sn", bid, r, CFAbsoluteTimeGetCurrent() - t0);
            }
        }
    });
}

@end
