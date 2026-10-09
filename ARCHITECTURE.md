# APTV IPA Analysis → Benzer iOS Uygulama Mimarisı

Kaynak: `APTV.ipa` → `extracted/Payload/APTV.app`  
Uygulama: **APTV** `com.kimen.aptvpro` v**9.4.5** (iOS 14+, iPhone + iPad)

> Not: Swift binary tam kaynak koda çevrilemez. Bu belge sınıf isimleri, bağımlılıklar ve plist’ten çıkan **mimari haritadır**. Kendi uygulamanı sıfırdan yaz.

## Ne iş yapıyor?

IPTV / canlı yayın oynatıcı:
- Uzaktan **M3U / TXT** canlı kaynak ekleme
- Kanal listesi, kategori, arama, favori
- **EPG** (XMLTV / DIYP)
- **KSPlayer + FFmpeg** ile HLS/TS vb. oynatma
- Proxy, CarPlay, Share Extension, RevenueCat abonelik

## Tech stack (yeniden kurarken kullan)

| Katman | APTV’de | Önerilen eşdeğer |
|--------|---------|------------------|
| UI | SwiftUI + UIKit (VC’ler) | SwiftUI |
| Layout | SnapKit | SwiftUI / Auto Layout |
| Network | Alamofire | URLSession / Alamofire |
| JSON | SwiftyJSON | Codable |
| Image | SDWebImage(+SwiftUI) | SDWebImage / Kingfisher |
| Player | KSPlayer + FFmpegKit | KSPlayer veya AVPlayer (+ FFmpeg gerekirse) |
| M3U | M3UKit | M3UKit veya kendi parser |
| Storage | Core Data | Core Data / SwiftData |
| Prefs | Defaults | UserDefaults / Defaults |
| IAP | RevenueCat | RevenueCat / StoreKit 2 |
| UPnP | SwiftUPnP | opsiyonel |
| HTML | Kanna (share) | opsiyonel |

## Ekran / ViewModel haritası

```
Config (kaynak listesi)     → ConfigViewModel, AddConfigViewModel, ConfigViewController
Channel list / category     → ChannelViewModel, ChannelListController, CategoryViewController
Channel detail / edit       → ChannelDetailViewModel, EditChannelModel, MergeChannel…
Program / EPG               → ProgramViewController, EpgXml, EpgUtil
Player                      → KSPlayerViewController, VideoPlayerViewModel, PlayerContainerViewModel
Settings / Pro / Purchase   → SettingViewModel, AptvProViewModel, PurchaseViewModel
CarPlay                     → CarPlaySceneDelegate
Share                       → aptvshare.appex
```

SwiftUI view isimleri (binary’den):  
`ChannelListView`, `ChannelDetailView`, `FavoriteView`, `SettingView`, `AddChannelView`, `ProgramView`, `ProxyView`, `ScanChannelView`, `MergeChannelListView`…

## Core Data modeli

Entities:
- **Config** — canlı kaynak (URL, tip, oluşturma zamanı…)
- **Item** — kanal / öğe
- **Favorite** — favoriler
- **Proxy** — host, port, username, password, type
- **RecentlyPlay** — son oynatılanlar

## URL / entegrasyonlar

- App: `https://aptv.app`, `https://play.aptv.app/`, `https://add.aptv.app/`
- EPG örnek: `https://epg.aptv.app/`, `pp.xml.gz`
- Docs: `https://docs.aptvapp.com/…`
- GitHub (referans): `https://github.com/Kimentanm/aptv`
- Altyazı: OpenSubtitles, assrt.net
- Deep link scheme: `aptv://`
- Bonjour: `_aptv._tcp`
- Dış oynatıcı: Infuse, VLC (`LSApplicationQueriesSchemes`)
- ATS: `NSAllowsArbitraryLoads = true` (HTTP M3U için)

## Bundle özellikleri

- Alternate app icons (çoklu)
- Background: `audio`, `fetch`, `remote-notification`
- Document browser + LocalConfig document type
- Yerelleştirme: en, tr, ja, vi, zh-Hans/Hant/HK
- Share Extension: `aptvshare.appex`

## Çıkarılmış klasör

```
extracted/Payload/APTV.app/
  APTV                 # ana binary (~53 MB)
  Info.plist
  Frameworks/          # FFmpeg, KSPlayer bağımlılıkları…
  PlugIns/aptvshare.appex/
  Model.momd/
  *.lproj/
  kanal ikonları (png)
```

Ayrıca: `Info.plist.json`, `localizable_keys.json`, `ARCHITECTURE.md`
