# Aptvios 1.2

APTV özellik paritesine yaklaşan SwiftUI IPTV oynatıcı — birçok noktada daha sade/modern.

## Kaynak tipleri

| Tip | Durum |
|-----|--------|
| M3U / TXT (URL, yapıştır, dosya) | ✅ |
| Xtream Codes | ✅ |
| Stalker Portal (MAG live) | ✅ |
| Tek kanal / boş kaynak | ✅ |
| Kanal tarama `(0-9)` / `(0-f)` | ✅ |

## Oynatma & EPG

| Özellik | Durum |
|---------|--------|
| AVPlayer | ✅ |
| KSPlayer (FFmpeg, SPM) | ✅ |
| Dış oynatıcı (VLC / Infuse) | ✅ |
| Çoklu ekran (2 panel) | ✅ |
| XMLTV EPG (+ gzip) | ✅ |
| DIYP EPG | ✅ |
| Altyazı arama (OpenSubtitles / assrt) | ✅ |
| CarPlay (favori, kategori, ara, EPG, next/prev) | ✅ |

## Yönetim

| Özellik | Durum |
|---------|--------|
| Favori / son izlenen | ✅ |
| Kanal düzenle / sil | ✅ |
| Kanal birleştirme | ✅ |
| Proxy | ✅ |
| Bonjour yerel paylaşım | ✅ |
| iCloud senkron (opsiyonel, restart) | ✅ |
| Önizleme thumbnail (deneysel) | ✅ |

## APTV’den hâlâ farklı / eksik

- Resmi Share Extension target (yerine Bonjour + deep link)
- UPnP / DLNA tam istemci
- tvOS / macOS / watchOS hedefleri
- RevenueCat Pro mağazası
- Yerleşik yüzlerce kanal ikonu paketi
- CarPlay **Audio** entitlement (Apple Developer onayı gerekir); Video CarPlay ayrı program

> Not: APTV’nin kodu/asset’i kopyalanmaz; özellik paritesi hedeflenir.

## Mac’te çalıştırma

```bash
open Aptvios.xcodeproj
```

1. Signing Team seç  
2. (İsteğe bağlı) Signing → Capability → iCloud → `iCloud.com.aptvios.app`  
3. Run — KSPlayer ilk seferde büyük binary indirebilir  

Test: `Sample/demo.m3u`
