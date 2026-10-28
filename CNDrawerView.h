#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Trebuchet tarzı tam ekran uygulama çekmecesi.
/// progress: 0 = kapalı, 1 = açık. Parmakla sürüklerken doğrudan ayarlanır.
@interface CNDrawerView : UIView

@property (nonatomic, assign) CGFloat progress;
@property (nonatomic, readonly) BOOL isOpen;

/// Yüklü uygulamaları yeniden okur (çekmece her açılmadan önce çağrılır).
- (void)reloadApps;

/// Açık/kapalı konuma yaylı animasyonla oturtur. velocityY: nokta/sn (yukarı negatif).
- (void)settleOpen:(BOOL)open velocity:(CGFloat)velocityY;

@end

NS_ASSUME_NONNULL_END
