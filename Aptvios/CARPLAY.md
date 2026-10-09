# CarPlay (APTV özellik paritesi)

## Sekmeler
1. **Favoriler** — yıldızlı kanallar  
2. **Son** — son izlenenler  
3. **Kategoriler** — grup → kanal listesi  
4. **Kanallar** — gruplu tam liste + playing indicator  
5. **Ara** → `CPSearchTemplate` (isim / grup / tvg-id)  
6. **Now Playing** — metadata + butonlar

## Now Playing
- Önceki / Sonraki kanal  
- Favoriye ekle-çıkar  
- Yeniden bağlan (reload stream)  
- Kilit ekranı / direksiyon kontrolleri (`MPRemoteCommandCenter`)  
- EPG “şimdi / sonraki” Now Playing artist/album alanında  
- Logo artwork (varsa)

## Satır detayı
- `▶ Program adı · bitiş saati` (EPG yüklüyse)  
- Aksi halde grup adı  
- Kanal logosu (async)

## Gereksinimler (cihaz)
1. Apple Developer → App ID → **CarPlay Audio** (+ Playable Content)  
2. Provisioning profile yenile  
3. Xcode Signing’de entitlement’lar aktif  
4. Gerçek CarPlay ünitesi veya Xcode → I/O → External Displays → CarPlay Simulator  

Simulator’da entitlement olmadan bazen bağlanır; App Store / cihaz için onay şart.
