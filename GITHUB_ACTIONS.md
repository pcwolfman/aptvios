# Ücretsiz GitHub Actions ile derleme

Windows’ta Xcode yok; GitHub’ın **macOS runner**’ı projeyi derler. İmza / App Store yükleme yok — sadece “derleniyor mu?” kontrolü.

## 1) Repo oluştur ve yükle

PowerShell (proje klasöründe):

```powershell
cd c:\Users\pcmy\Downloads\aptvios
git init
git add .
git commit -m "Initial Aptvios project with CI"
```

GitHub’da boş repo aç (önerilen: **Public** — ücretsiz macOS dakikası daha rahat), sonra:

```powershell
git branch -M main
git remote add origin https://github.com/pcwolfman/aptvios.git
git push -u origin main
```

Bu makinede remote zaten `https://github.com/pcwolfman/aptvios.git` olarak ayarlandı.

Hızlı yol (`gh` yüklü):

```powershell
gh auth login
gh repo create aptvios --public --source=. --remote=origin --push
```

(Repo yoksa web: https://github.com/new?name=aptvios — Public seç, Create, sonra sadece `git push -u origin main`)

## 2) Sonucu gör

GitHub → **Actions** → **iOS Build**  
Yeşil = Simulator build başarılı. Kırmızı = log’u aç, hatayı gönder.

## 3) Elle tekrar çalıştır

Actions → iOS Build → **Run workflow**

## Limitler

| Repo | macOS dakikası |
|------|----------------|
| Public | Genelde bol (fair use) |
| Private (free) | Aylık sınırlı (GitHub planına göre) |

KSPlayer ilk seferde paket indirdiği için build **15–40 dk** sürebilir.

## Bu CI ne yapmaz?

- Cihaza IPA yüklemez  
- App Store’a göndermez  
- CarPlay entitlement onayı vermez  

Sadece: kod Mac’te derleniyor mu.

## Workflow dosyası

`.github/workflows/ios-build.yml`
