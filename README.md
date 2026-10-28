# Cannon (v0.0.1, derlenmedi, test edilmedi)

iOS 15 (palera1n rootless, iPhone 7) için Trebuchet tarzı yukarı kaydırmalı uygulama çekmecesi.
App Library yerinde kalır, çekmece ayrıca eklenir.

## Derleme (GitHub Actions)
1. Bu klasörü bir GitHub deposuna yükle (`.github` klasörü dahil).
2. Actions sekmesi > "Build Cannon" > Run workflow.
3. Bitince çıktıdaki `cannon-deb` dosyasından `.deb`'i indir, Filza/Sileo ile kur, respring.
Linux runner'da hata verirse (özellikle ldid ile ilgili), log'u gönder; `runs-on: macos-latest` denenebilir.

## Jest
Ana ekranda, alt kenardan ~50pt yukarıdan başlayarak yukarı kaydır. (Alt kenar Control Center'a ait.)
Kapatmak için: karartmaya dokun veya liste en üstteyken aşağı çek.

## Doğrulanacaklar (cihazda)
- `SBHomeScreenViewController` sınıfı ve `viewDidLoad` hook'u (log: `[Cannon] jest eklendi`)
- `UIImage _applicationIconImageForBundleIdentifier:format:scale:` için `kIconFormat` (CNDrawerView.m)
- Uygulama listesi: LSApplicationWorkspace allInstalledApplications / appTags "hidden" filtresi
- Home tuşuyla çekmece kapanmıyor (v0.1'de yok)
- Kenar boşlukları ve köşe yarıçapı (28pt) tahmin

## Trebuchet'ten alınan değerler (lineage-20.0, Apache 2.0 kaynak referansı)
4 sütun, ikon 60, yazı 14, hücre yüksekliği 104, hücre aralığı 16, arama alanı 48 yükseklik ve hap şekli.
