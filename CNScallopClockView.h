#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Android 12+ Material You "Scallop" analog saat: 12 dilimli kenar, kalın yuvarlak yelkovan ve akrep.
/// Eller CAShapeLayer + dönüş dönüşümü ile çizilir; yalnızca dakikada bir güncellenir (A10'da ısı/pil dostu).
@interface CNScallopClockView : UIView

@property (nonatomic, strong) UIColor *faceColor;     // saat yüzü
@property (nonatomic, strong) UIColor *hourColor;     // akrep
@property (nonatomic, strong) UIColor *minuteColor;   // yelkovan
@property (nonatomic, strong) UIColor *dotColor;      // saniye noktası
/// Kenardaki küçük saniye noktası. Her saniye güncelleme gerektirdiği için varsayılan kapalı.
@property (nonatomic, assign) BOOL showsSecondDot;

@end

NS_ASSUME_NONNULL_END
