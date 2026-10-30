#import "CNScallopClockView.h"

// Ölçüler, kullanıcının paylaştığı Android "Scallop" saat görselinden oranlanmıştır (boyuta göre).
static const NSInteger kLobes = 12;          // kenardaki dilim sayısı
static const CGFloat kLobeDepth = 0.05;      // dilim derinliği (yarıçapa oran), tahmin
static const CGFloat kHandWidth = 0.086;     // el kalınlığı
static const CGFloat kHourLength = 0.25;     // akrep uzunluğu
static const CGFloat kMinuteLength = 0.34;   // yelkovan uzunluğu
static const CGFloat kDotRadius = 0.05;      // saniye noktası yarıçapı
static const CGFloat kDotOrbit = 0.416;      // saniye noktasının merkeze uzaklığı

@interface CNScallopClockView ()
@property (nonatomic, strong) CAShapeLayer *faceLayer;
@property (nonatomic, strong) CAShapeLayer *hourLayer;
@property (nonatomic, strong) CAShapeLayer *minuteLayer;
@property (nonatomic, strong) CAShapeLayer *dotLayer;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation CNScallopClockView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        _faceColor = [UIColor colorWithRed:0.882 green:0.961 blue:0.906 alpha:1.0];
        _hourColor = [UIColor colorWithRed:0.247 green:0.298 blue:0.263 alpha:1.0];
        _minuteColor = [UIColor colorWithRed:0.235 green:0.553 blue:0.388 alpha:1.0];
        _dotColor = [UIColor colorWithRed:0.322 green:0.502 blue:0.604 alpha:1.0];

        _faceLayer = [CAShapeLayer layer];
        _hourLayer = [CAShapeLayer layer];
        _minuteLayer = [CAShapeLayer layer];
        _dotLayer = [CAShapeLayer layer];
        for (CAShapeLayer *l in @[_hourLayer, _minuteLayer]) {
            l.fillColor = nil;
            l.lineCap = kCALineCapRound;
        }
        [self.layer addSublayer:_faceLayer];
        [self.layer addSublayer:_hourLayer];
        [self.layer addSublayer:_minuteLayer];
        [self.layer addSublayer:_dotLayer];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateHands)
                                                     name:NSSystemClockDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [self.timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark Çizim

- (UIBezierPath *)scallopPathInRect:(CGRect)r {
    CGPoint c = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    CGFloat R = MIN(r.size.width, r.size.height) / 2.0 / (1.0 + kLobeDepth);
    UIBezierPath *p = [UIBezierPath bezierPath];
    const int steps = 360;
    for (int i = 0; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps * 2.0 * M_PI;
        CGFloat rad = R * (1.0 + kLobeDepth * cos(kLobes * t));
        CGPoint pt = CGPointMake(c.x + rad * sin(t), c.y - rad * cos(t));
        if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
    }
    [p closePath];
    return p;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat S = MIN(b.size.width, b.size.height);
    CGPoint c = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));

    for (CALayer *l in @[self.faceLayer, self.hourLayer, self.minuteLayer, self.dotLayer]) l.frame = b;

    self.faceLayer.path = [self scallopPathInRect:b].CGPath;
    self.faceLayer.fillColor = self.faceColor.CGColor;

    UIBezierPath *hour = [UIBezierPath bezierPath];
    [hour moveToPoint:c];
    [hour addLineToPoint:CGPointMake(c.x, c.y - S * kHourLength)];
    self.hourLayer.path = hour.CGPath;
    self.hourLayer.strokeColor = self.hourColor.CGColor;
    self.hourLayer.lineWidth = S * kHandWidth;

    UIBezierPath *minute = [UIBezierPath bezierPath];
    [minute moveToPoint:c];
    [minute addLineToPoint:CGPointMake(c.x, c.y - S * kMinuteLength)];
    self.minuteLayer.path = minute.CGPath;
    self.minuteLayer.strokeColor = self.minuteColor.CGColor;
    self.minuteLayer.lineWidth = S * kHandWidth;

    CGFloat dr = S * kDotRadius;
    self.dotLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - dr, c.y - S * kDotOrbit - dr, dr * 2, dr * 2)].CGPath;
    self.dotLayer.fillColor = self.dotColor.CGColor;
    self.dotLayer.hidden = !self.showsSecondDot;

    [self updateHands];
}

- (void)setShowsSecondDot:(BOOL)showsSecondDot {
    _showsSecondDot = showsSecondDot;
    self.dotLayer.hidden = !showsSecondDot;
    [self scheduleTimer];
}

#pragma mark Zaman

- (void)updateHands {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *dc = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:[NSDate date]];
    CGFloat sec = dc.second, min = dc.minute + sec / 60.0, hr = (dc.hour % 12) + min / 60.0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.hourLayer.transform = CATransform3DMakeRotation(hr / 12.0 * 2.0 * M_PI, 0, 0, 1);
    self.minuteLayer.transform = CATransform3DMakeRotation(min / 60.0 * 2.0 * M_PI, 0, 0, 1);
    self.dotLayer.transform = CATransform3DMakeRotation(sec / 60.0 * 2.0 * M_PI, 0, 0, 1);
    [CATransaction commit];
}

- (void)scheduleTimer {
    [self.timer invalidate];
    self.timer = nil;
    if (!self.window) return;   // ekranda değilken zamanlayıcı çalışmasın
    NSTimeInterval step = self.showsSecondDot ? 1.0 : 60.0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSDate *first = [NSDate dateWithTimeIntervalSince1970:(floor(now / step) + 1.0) * step];  // saniye/dakika başında
    __weak typeof(self) weakSelf = self;
    self.timer = [[NSTimer alloc] initWithFireDate:first interval:step repeats:YES block:^(NSTimer *t) {
        [weakSelf updateHands];
    }];
    self.timer.tolerance = 0.2;
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateHands];
    [self scheduleTimer];
}

@end
