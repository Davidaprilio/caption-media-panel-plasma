# Arsitektur Caption Media Panel

Target: KDE Plasma 6 (dites di Plasma 6.7.5, Qt 6.11, Wayland, CachyOS).

## Prinsip

1. **Pure QML di dalam plasmashell.** Widget panel berjalan di dalam proses `plasmashell`.
   Tanpa kode native, widget tidak bisa membuat panel crash, dan tidak perlu proses build.
2. **Event-driven, tanpa polling.** Tidak ada timer yang aktif saat media di-pause atau tidak ada player.
3. **Pekerjaan berat di luar plasmashell.** Sumber transcript yang berat (unduhan, speech-to-text)
   nanti dijalankan sebagai proses terpisah, misalnya daemon yang bicara lewat D-Bus. Widget hanya menerima cue jadi.

## Alur data

```
 MPRIS (D-Bus) ──► MediaSource.qml ──► CueClock.qml ◄── TranscriptSource.qml (router)
                   playing, rate,      posisi interpolasi,   providers: [ (urutan = prioritas)
                   position, track,    currentIndex, active    NeteaseProvider       (musik → lirik + romaji)
                                                               YouTubeMusicProvider  (musik → lirik Musixmatch/LyricFind)
                                                               LrclibProvider        (musik → lirik)
                                                               YouTubeProvider  (URL YouTube → caption)
                                                               DummyProvider    (fallback) ]
                                                             semua mengimplementasikan TranscriptProvider
                   url (via busctl)                          cues[] {start,end,text}
                                              │
                      ┌───────────────────────┴───────────────────┐
              CompactRepresentation (panel)           FullRepresentation (popup)
              ├─ LyricView   (baris naik, 1-5 baris)  daftar transcript, highlight,
              └─ MarqueeView (geser saat overflow)    klik baris = seek
```

| File | Peran |
|---|---|
| `ui/MediaSource.qml` | Adapter **satu-satunya** ke `org.kde.plasma.private.mpris` (API private Plasma). Kalau API itu berubah, cukup file ini yang diubah. Player yang diikuti dipilih sendiri (lihat "Pemilihan player"). |
| `ui/CueClock.qml` | Menentukan cue yang sedang tampil berdasarkan posisi player. |
| `ui/TranscriptSource.qml` | Router generik: memilih provider untuk media saat ini, lalu meneruskan output-nya. Daftar provider diisi di `main.qml`. |
| `ui/providers/TranscriptProvider.qml` | **Interface** semua service transkrip (lihat "Menambah service transkrip"). |
| `ui/providers/HttpClient.qml` | HTTP async bersama untuk provider: header, timeout, retry untuk 503/429 (mengikuti `Retry-After`), pembatalan, dan pengabaian jawaban basi. |
| `ui/providers/YouTubeProvider.qml`, `code/youtube.js` | Transkrip asli YouTube (lihat di bawah). |
| `ui/providers/NeteaseProvider.qml`, `code/netease.js` | Lirik tersinkron + romanisasi dari NetEase Cloud Music (lihat di bawah). |
| `ui/providers/YouTubeMusicProvider.qml`, `code/ytmusic.js` | Lirik tersinkron dari YouTube Music (lihat di bawah). |
| `code/match.js` | Aturan pencocokan hasil pencarian (durasi, artis, judul, versi lain), dipakai NetEase dan YouTube Music. |
| `ui/providers/LrclibProvider.qml`, `code/lrclib.js` | Lirik tersinkron dari LRCLIB untuk Spotify dan YouTube Music (lihat di bawah). |
| `ui/providers/DummyProvider.qml` | Provider fallback berisi teks dummy. |
| `code/cues.js` | Binary search, batas cue berikutnya, dan helper. |
| `code/dummyTranscript.js` | Teks dummy. |
| `ui/LyricView.qml`, `ui/MarqueeView.qml` | Tampilan di panel. |
| `ui/FullRepresentation.qml` | Popup transcript. Baru dibuat saat pertama kali dibuka. |
| `ui/EqualizerBars.qml` | Equalizer di panel dan di header popup: mengikuti `levels` kalau ada, dekoratif kalau tidak. Warna `root.equalizerColor` (aksen atau `equalizerColor`), opacity `panelEqualizerOpacity` / `popupEqualizerOpacity`. |
| `ui/AudioLevels.qml`, `code/cava_bridge.py` | Level audio sungguhan dari cava (config `equalizerFollowsAudio`), lihat "Equalizer mengikuti audio". |

## Sinkronisasi waktu (CueClock)

MPRIS tidak mengirim `Position` secara berkala. Player hanya mengirimnya saat seek (`Seeked`) atau ketika diminta.
Karena itu CueClock bekerja seperti ini:

- Menyimpan `basePos` dan `baseTs`. Posisi saat ini = `basePos + (now − baseTs) × rate`.
- Setiap kali ada sync, CueClock mencari cue aktif dengan binary search, lalu menjadwalkan **satu Timer single-shot**
  ke batas cue berikutnya (akhir cue aktif atau awal cue berikutnya).
- Timer Qt bersifat *coarse* (meleset ±5%). Untuk penantian panjang, CueClock bangun 150 ms lebih awal,
  lalu memakai penantian pendek kedua supaya pas di batas. Hasil ukur: baris berganti 3–12 ms setelah jadwal.
- Saat media diputar, CueClock meminta `updatePosition()` tiap 5 detik untuk mengoreksi drift.
  Pause, play, dan perubahan rate otomatis memicu permintaan posisi baru.
- Saat media di-pause, posisi interpolasi dibekukan dan semua timer berhenti.

> Catatan penting: di handler `positionChanged`, nilai harus dibaca langsung dari `player.position`
> (`MediaSource.positionMs()`). Binding turunan bisa masih berisi nilai lama saat handler berjalan.

## Transkrip YouTube

**Deteksi.** Paket Plasma Browser Integration (PBI) mengekspos `xesam:url`, yaitu URL halaman yang sedang memutar media,
lewat player `org.mpris.MediaPlayer2.plasma-browser-integration`. Untuk browser lain, PBI butuh ekstensi browser-nya terpasang.
kmpris tidak meneruskan URL itu ke QML. Karena itu `MediaSource` menjalankan `busctl` (lewat engine
`executable` dari Plasma5Support) sekali setiap kali track berganti. URL dipakai hanya kalau:
- `kde:pid` PBI sama dengan `kdePid` atau `instancePid` player saat ini. Multiplexer kmpris kadang tetap memilih
  player bawaan browser, bukan proxy PBI, jadi kedua kemungkinan itu diterima.
- Judul PBI ada di dalam judul player. Player bawaan Chromium menambahkan "(3) … - YouTube" pada judul.

Dari metadata PBI yang sama, widget juga mengambil judul, artis, album, dan artwork, lalu memprioritaskannya di atas
data player yang diikuti. Player bawaan browser mengirim data yang kurang lengkap, misalnya untuk YouTube Music judulnya
"Lagu | YouTube Music" tanpa artis, sehingga LRCLIB tidak bisa mencari liriknya.

**Pengambilan transkrip** dilakukan lewat QML `XMLHttpRequest` (async, tanpa dependency tambahan):
1. `POST /youtubei/v1/player` dengan client InnerTube ANDROID (fallback ke IOS) untuk mendapat daftar caption track.
2. `GET` caption track dengan `fmt=json3`, lalu `json3ToCues()` mengubahnya menjadi cue.

Track dipilih dengan urutan: caption manual dulu, baru auto-generated. Bahasa sistem diutamakan, lalu bahasa Inggris.
Caption ASR bergaya *rolling* sehingga saling tumpang tindih; akhir setiap cue dipotong ke awal cue berikutnya.
Hasilnya di-cache di memori untuk 8 video terakhir.

**Keterbatasan (diuji Oktober 2026):**
- Ini API tidak resmi. URL caption dari halaman web (`exp=xpe`) butuh PO token dan mengembalikan body kosong.
  Client mobile saat ini masih bisa dipakai tanpa token. Kalau nanti rusak, ubah versi atau urutan client di `CLIENTS` (`code/youtube.js`).
- Terjemahan otomatis (`&tlang=`) kena HTTP 429, jadi belum dipakai.
- Tanpa PBI (misalnya Firefox tanpa ekstensi), URL tidak tersedia dan video YouTube diperlakukan sebagai media lain.
- Saat iklan YouTube diputar, posisi player adalah posisi iklan, sehingga caption tidak cocok selama iklan berjalan.

## Lirik Spotify dan YouTube Music (LRCLIB)

`LrclibProvider` aktif kalau `identity` atau `desktopEntry` player cocok dengan `players` (default `["spotify"]`),
atau kalau URL halamannya diawali `https://open.spotify.com/` (Spotify Web lewat PBI) atau `https://music.youtube.com/`.
Syarat lainnya: judul dan artis tidak kosong, sehingga iklan Spotify jatuh ke fallback.

Urutan untuk musik (Spotify, YouTube Music) adalah **NetEase → YouTube Music → LRCLIB → caption YouTube**; caption YouTube hanya
berlaku untuk YouTube Music. Lirik diutamakan karena caption video musik di YouTube sering berupa terjemahan
(contoh: MV resmi 優里 – ドライフラワー hanya punya caption Inggris, Mandarin, dan Korea). Video YouTube biasa hanya
diklaim oleh `YouTubeProvider`.

Setiap lagu memakai paling banyak dua request (header `User-Agent: caption-media-panel/…`):
1. `GET /api/get` dengan judul, artis, album, dan durasi (toleransi ±2 detik).
2. Kalau tidak ada hasil tersinkron, `GET /api/search` dengan judul yang dibersihkan (tanpa "- Remastered…" dan
   "(feat. …)") serta artis pertama. Hasil dipilih berdasarkan durasi terdekat (maksimal ±3 detik), supaya tidak
   tertukar dengan versi live atau edit.

Catatan dari pengujian (Oktober 2026):
- Untuk lagu yang entrinya tidak persis ada, `/api/get` sering dijawab **503** (server mencari ke sumber luar,
  lalu antreannya penuh). Karena itu 503 di langkah 1 langsung dilanjutkan ke search tanpa menunggu. Search diulang
  sampai 2 kali kalau mendapat 503/429.
- `/api/get-cached` menjawab 404 bahkan untuk lagu yang ada, jadi tidak dipakai.
- Hasil "tidak ditemukan" di-cache, tetapi request yang gagal tidak, sehingga lagu itu dicoba lagi saat diputar ulang.
- Entri yang hanya punya `plainLyrics` (tanpa `syncedLyrics`) tidak dipakai sebagai lirik tersinkron, tetapi disimpan
  sebagai cadangan (`pickPlain()`, durasi ±3 detik) untuk ditampilkan sebagai teks biasa di popup.
- kmpris mengubah metadata satu per satu: judul berubah lebih dulu, baru durasi. Pencarian ditunda dengan
  `Qt.callLater` supaya memakai durasi lagu yang benar.

LRC yang didukung: beberapa timestamp dalam satu baris, `[offset:±ms]`, tag word-timing `<mm:ss.xx>` (diabaikan),
baris kosong sebagai jeda, dan lagu instrumental (satu cue "♪ Instrumental ♪").

## Lirik dan romanisasi NetEase

`NeteaseProvider` menangani media yang sama dengan LRCLIB. Setiap lagu butuh 1 pencarian dan 1–4 request lirik
(API tidak resmi, tanpa key). Satu respons lirik berisi `lrc` (asli), `romalrc` (romanisasi, misalnya romaji) dan
`tlyric` (terjemahan Mandarin), semuanya tersinkron.

- **Romanisasi:** dengan `preferRomanized` (default aktif), setiap baris memakai teks romanisasi kalau ada untuk
  timestamp itu, dan teks asli kalau tidak ada (misalnya baris berbahasa Inggris di lagu Jepang). Gaya romaji
  NetEase per suku kata ("ta bu n、wa ta shi ja na ku te"). Romanisasi Korea-nya tidak baku.
- **Pencocokan lagu** (`rankSongs`, aturannya di `code/match.js`): durasi harus cocok (±3 detik). Unggahan yang menaruh
  nama artis di judul ("Perunggu Ini Abadi" oleh akun pengunggah) cocok dengan kandidat yang judul dan artisnya
  sama-sama muncul di judul itu. Hiasan video seperti "(Official Music Video)" atau "[Lirik]" dibuang dulu. Lalu salah satu syarat ini harus terpenuhi:
  artis cocok, judul terjemahan (`transNames`) cocok, atau judul cocok dengan aksara non-Latin. Pemutar sering
  menulis artis Asia dalam romaji ("Yuuri" untuk 優里). Lagu berjudul sama dari artis lain ditolak, begitu juga versi
  lain (live, cover, "Chinese Version") kecuali media itu sendiri versi tersebut. Unggahan tanpa artis resmi
  (artist id 0) diberi prioritas lebih rendah. Rilisan lain dari lagu yang sama (judul dan artist id sama) ikut jadi
  kandidat, karena hanya sebagian rilisan yang punya romanisasi.
- **Percobaan:** sampai 4 kandidat dicoba berurutan. Yang pertama punya lirik tersinkron dan romanisasi langsung
  dipakai. Kalau tidak ada yang punya romanisasi, dipakai lirik asli dari kandidat pertama yang punya lirik.
- **Cookie:** setiap endpoint NetEase memasang cookie `NMTID`. Klien yang mengirimnya kembali mendapat hasil
  pencarian acak (diuji: 4 dari 4 pencarian berikutnya salah lagu). QML `XMLHttpRequest` selalu memakai cookie jar
  bersama plasmashell, dan header `Cookie` tidak bisa ditimpa. Karena itu `HttpClient { cookieless: true }` mengirim
  request lewat `curl` (tanpa cookie jar), dengan URL yang dikutip aman untuk shell karena judul berasal dari
  player atau halaman web.

## Lirik YouTube Music

YouTube Music menampilkan lirik berlisensi dari Musixmatch dan LyricFind. Lewat API internal (InnerTube, tanpa login)
lirik itu bisa diambil **tersinkron per baris**:

1. `next` (client web `WEB_REMIX`) dengan videoId menghasilkan `browseId` tab lirik (`pageType` `MUSIC_PAGE_TYPE_TRACK_LYRICS`).
2. `browse` dengan **client mobile `ANDROID_MUSIC`** menghasilkan `timedLyricsData` (`lyricLine` + `cueRange` dalam ms).
   Client web hanya mendapat teks biasa.
3. `search` (filter "Songs") untuk mendapat videoId versi lagu dari judul dan artis.

Alurnya:
- **YouTube Music:** videoId dari URL dipakai dulu (2 request). Lirik di **video klip** sering tanpa timestamp,
  sedangkan versi "song"-nya tersinkron. Karena data *counterpart* tidak tersedia tanpa login, versi song dicari lewat
  `search` (+3 request).
- **Spotify:** `search`, lalu `next` + `browse` (3 request).
- Lirik dianggap tersinkron hanya kalau **semua baris** punya `cueRange`. Lirik tanpa timestamp disimpan sebagai
  cadangan (`plainLyrics()`) dan hanya tampil sebagai teks biasa di popup kalau tidak ada sumber lain yang tersinkron.
- Tidak ada romanisasi, selalu aksara asli. Karena itu NetEase tetap di urutan pertama.

Uji Oktober 2026: 8 dari 8 lagu (Barat, Indonesia, Jepang, Korea) tersinkron lewat versi song-nya, sama untuk wilayah
ID dan US. Versi client mobile (`ANDROID_MUSIC` 7.21.50) dan filter Songs ada di `code/ytmusic.js`. Kalau YouTube
mengubahnya, provider ini gagal dan router beralih ke LRCLIB.

## Pemilihan player

`Mpris2Model.currentPlayer` (multiplexer kmpris) tidak selalu bisa diandalkan:
- Kadang tetap menunjuk player bawaan browser yang sudah disaring dan digantikan oleh proxy PBI.
- Tidak berpindah ke player yang baru mulai memutar kalau nomor baris player aktif kebetulan sama.

Karena itu `MediaSource._choosePlayer()` memilih sendiri. Player bawaan browser selalu diganti dengan proxy PBI-nya
(`kdePid` proxy = `instancePid` player bawaan). Player bawaan Chrome, misalnya, mengirim judul "YouTube Music"
untuk setiap lagu tanpa artis, sehingga pergantian lagu pun tidak terdeteksi. Setelah itu:
1. Player yang sedang diikuti dipertahankan selama masih memutar.
2. Kalau tidak, dipilih player yang sedang memutar, dengan pilihan multiplexer diutamakan.
3. Kalau tidak ada yang memutar, player sebelumnya dipertahankan selama masih ada (sticky). Dengan begitu,
   mem-pause Spotify tidak memindahkan widget ke tab browser.

**Browser tanpa Plasma Browser Integration.** Kalau yang diikuti tetap player bawaan sebuah browser (`kdePid` 0, nama
atau desktop entry seperti chrome/edge/brave/firefox) dan pencarian metadata PBI selesai tanpa hasil, berarti PBI atau
ekstensinya tidak aktif untuk browser itu (kalau aktif, `_choosePlayer()` pasti sudah pindah ke proxy-nya). Contohnya
Edge di Kubuntu, yang hanya melaporkan "A site is playing media" tanpa artis. `MediaSource.needsBrowserIntegration`
menandai kondisi ini. Transcript dummy tidak mengisi tempatnya, dan popup menampilkan "Can't tell what … is playing"
beserta tombol menuju panduan setup di README (`#browser-media`).

## Equalizer mengikuti audio

```
cava (PipeWire, 20 bar, 30 fps, ASCII) ─stdout─► cava_bridge.py ─WebSocket 127.0.0.1:47213─► AudioLevels.qml (main.qml)
                                                                                                 ├─► EqualizerBars di panel
                                                                                                 └─► EqualizerBars di popup
```

- `AudioLevels` dimuat lewat `Loader` di `main.qml`, tidak dideklarasikan langsung, karena butuh modul QML
  `QtWebSockets` yang di beberapa distribusi dipaket terpisah (Debian/Ubuntu: `qml6-module-qtwebsockets`, tidak ikut
  terpasang bersama Plasma). Dulu modul yang hilang membuat seluruh applet gagal dimuat. Sekarang equalizer kembali
  dekoratif (`root.audioLevels` jatuh ke objek dengan `levels: null`). Halaman pengaturan menyebutkan apa yang belum
  terpasang: modulnya dicek dengan mengompilasi `AudioLevels.qml` tanpa membuat objeknya, cava dan python3 dengan
  `command -v`.
- Hanya ada **satu** `AudioLevels` (di `main.qml`, `root.audioLevels`), jadi cava dan FFT berjalan sekali walaupun
  kedua equalizer tampil. Sumber ini aktif kalau equalizer panel tampil dan media sedang diputar, atau popup terbuka
  dengan equalizer aktif.
- Equalizer panel memasang level langsung tanpa animasi perantara (`animateLevels: false`), jadi panel digambar ulang
  sekitar 30 kali per detik saja. Equalizer popup memakai animasi singkat supaya lebih halus. Equalizer panel tidak
  tampil di panel vertikal.

- Penangkapan audio tidak boleh terjadi di dalam plasmashell, jadi cava dan bridge berjalan sebagai proses terpisah.
  `AudioLevels` menyalakan bridge lewat engine `executable` saat popup dibuka dan menerima data lewat `QtWebSockets`.
  Begitu koneksi ditutup (popup disembunyikan), bridge menghentikan cava dan keluar sendiri setelah 2 detik.
- Bridge hanya memakai library standar, berupa satu loop `select()` dengan modul bawaan yang kecil. Kalau beberapa
  frame menumpuk, hanya frame terbaru yang dikirim. Kalau cava tidak ada, bridge keluar dengan kode 2 dan widget
  kembali ke mode dekoratif.
- Bridge bisa dibunuh paksa: saat plasmashell di-restart atau logout, `QProcess` mengirim SIGKILL. Karena itu tidak
  ada yang boleh bergantung pada proses pembersihan bridge. cava dijalankan lewat `setpriv --pdeathsig TERM`, sehingga
  kernel mematikannya begitu bridge mati. File konfigurasi cava dihapus segera setelah cava mulai mengeluarkan data,
  dan file basi milik bridge yang sudah mati dibersihkan setiap kali bridge start.
- cava menangkap **semua** suara yang keluar dari speaker (monitor dari sink default), bukan hanya player yang diikuti.
- Biaya terukur (Oktober 2026, `schedstat`, governor powersave): cava ~1,0% dan bridge ~0,5% dari satu core,
  RAM ~15 MB + ~12 MB, dan itu hanya selama popup terbuka. Sebagai pembanding, prototipe Python+numpy butuh ~2,6% dan
  ~35 MB. Versi pertama bridge yang memakai asyncio justru lebih boros daripada cava (1,4%, 25 MB).

## Scroll di popup

- Highlight dan scroll di popup diatur sendiri (`showIndex()`), bukan oleh ListView: baris aktif digeser halus ke
  tengah, lompatan jauh (lebih dari 3 baris) langsung tanpa animasi, dan tidak ada scroll selama popup tertutup.
- **Mode ikut (`following`)**: begitu pengguna menggulir sendiri, auto-scroll berhenti. Highlight tetap pindah
  mengikuti lagu, dan muncul tombol pill **"Follow lyrics"** ("Follow captions" untuk caption YouTube). Panahnya menunjuk
  ke arah baris yang sedang diputar. Klik tombol itu untuk scroll halus ke baris tersebut, sejauh apa pun, lalu daftar
  kembali mengikuti. Popup juga kembali mengikuti saat dibuka ulang, saat transcript berganti, dan saat sebuah baris
  diklik (seek). Baris yang diklik dan sedang terlihat di layar digeser halus ke tengah, tidak melompat.
- Deteksi: ScrollView Plasma menggulir roda mouse dan touchpad lewat `Kirigami.WheelHandler`. Handler itu adalah event
  filter yang menelan event dan tidak memancarkan `movementStarted`. Karena itu ada `MouseArea` transparan di atas daftar
  (`acceptedButtons: Qt.NoButton`, `wheel.accepted = false`) yang melihat event roda lebih dulu lalu meneruskannya. Drag
  scrollbar dideteksi dari `ScrollBar.vertical.pressed`, dan flick di layar sentuh dari `movementStarted`.
- Saat scroll jauh, baris-baris yang dilewati baru ditata ketika dilalui, sehingga baris panjang yang terbungkus bisa
  membuat target meleset beberapa piksel. Setelah animasi selesai, sisanya diluncurkan sekali lagi (`_landed()`).

## Lebar di panel

- **Auto**: lebar baris terpanjang di transcript (mode lyric), atau baris terpanjang + jarak + slot 100 px untuk baris
  berikutnya (mode marquee), dibatasi `maxAutoWidth`.

Di mode marquee, baris berikutnya dipotong ke slot 100 px. Kalau teksnya lebih panjang, ujungnya memudar lewat mask
`MultiEffect` (layer GPU kecil, hanya aktif saat teks memang terpotong; di renderer software teks cukup dipotong). Nilainya dihitung sekali
  per transcript dengan `TextMetrics`, hanya untuk teks unik. Akibatnya, pergantian baris tidak memicu relayout
  panel, sehingga applet lain tidak ikut bergeser.
- **Manual**: lebar tetap dalam px.

Ukuran font otomatis mengecil kalau `N baris × tinggi baris` lebih besar dari tinggi panel.

## Performa (hasil ukur)

- Saat media diputar: 0 tick CPU dalam 20 detik (diukur di `plasmawindowed`, kurang dari 10 ms CPU).
- Saat di-pause atau idle: tidak ada timer dan tidak ada animasi.
- Animasi hanya berjalan sekitar 250 ms per pergantian baris (mode lyric), sekitar 375 ms saat strip marquee
  bergeser ke baris berikutnya, atau selama teks marquee yang terlalu panjang digulir.
- Marquee memakai dua label (baris aktif dan berikutnya), ditambah label ketiga yang hanya ada selama geseran: baris
  sesudahnya, yang ikut masuk dari kanan sampai tepat di posisi slot. Setelah geseran selesai, teks ditukar dan strip
  dikembalikan ke posisi awal tanpa terlihat, jadi tidak ada model atau delegate tambahan.
  Animasi otomatis mati kalau animasi Plasma dimatikan (`Kirigami.Units.longDuration == 0`).
- Mode ambient popup (`popupAmbient`): artwork di-decode kecil (64×64), di-blur dengan `MultiEffect`, lalu di-mask
  gradasi radial dari tengah thumbnail. Efek ini hanya dirender ulang saat artwork berubah, dan tidak dipakai di
  renderer software.
- Equalizer popup hanya beranimasi saat popup terbuka dan media diputar. Setelah itu bar turun ke posisi diam dan
  semua animasinya berhenti (diuji di `tests/tst_equalizer.qml`). Kalau dimatikan di setting, komponennya tidak dibuat.

## Menambah service transkrip

Setiap service adalah turunan dari `providers/TranscriptProvider.qml`:

| Bagian | Properti | Siapa yang mengisi |
|---|---|---|
| Deskripsi | `providerId`, `displayName`, `fallback`, `enabled` | provider (`enabled` boleh dari config) |
| Input | `media` (MediaSource), `languages`, `active` | `TranscriptSource` |
| Keputusan | `canHandle`: binding murah, "apakah media ini bisa saya layani?" | provider |
| Output | `cues`, `status` (enum `TranscriptProvider.Idle/Loading/Ready/Unavailable`), `sourceName`, `plainText` (lirik tanpa timestamp) | provider, lewat `setLoading()`, `setReady()`, `setUnavailable()`, `setPlainOnly()`, `setFromCache()`, `reset()` |
| Helper | `cached()` / `remember()` (cache memori), `HttpClient` | dipakai provider |

Aturan router (`TranscriptSource`):
1. Provider pertama (urut daftar) yang `enabled`, bukan `fallback`, dan `canHandle` akan dipakai.
2. **Berjenjang:** kalau provider itu berakhir `Unavailable` untuk media ini, provider non-fallback berikutnya yang
   juga `canHandle` dicoba (contoh: YouTube Music, caption YouTube lalu LRCLIB). Kalau semuanya habis, router tetap di
   provider terakhir (Unavailable, panel kosong). Fallback tidak pernah menggantikan media yang sudah diklaim provider
   asli. Daftar "sudah dicoba" di-reset setiap kali `trackKey` atau `url` berubah.
3. Kalau tidak ada provider non-fallback yang `canHandle`, dipakai fallback pertama yang `enabled`. Selama URL media
   masih dicari (`media.urlPending`), fallback ditahan dulu supaya tidak sempat muncul sekejap.
4. Hanya provider yang `active` boleh bekerja (request jaringan, proses). Provider lain memanggil `reset()`.
5. Supaya jenjang tidak dicoba berulang tanpa perlu, provider sebaiknya meng-cache hasil "tidak ada" yang pasti
   (bukan kegagalan jaringan). Contohnya `remember(key, { cues: [] })`, lalu `setFromCache(hit)` saat cache hit.
6. **Pemilih sumber (footer popup):** `candidates` berisi provider yang `enabled` dan `canHandle` untuk media saat ini
   (fallback hanya kalau tidak ada yang lain). Selama `probe` aktif (`root.expanded`, artinya popup terbuka), kandidat lain
   ikut mencari dengan `probing = true`, sehingga `available` (yang statusnya Ready) berisi semua sumber yang **punya
   lirik**. Hanya itu yang muncul di dropdown. Probe memakai request tambahan, jadi hanya berjalan saat popup terbuka,
   dan hasilnya tetap di cache provider. `pin(provider)` memakai sumber yang dipilih, dan pilihan itu hilang saat media
   berganti.
7. **Lirik tanpa sinkron:** provider bisa menyerah (`Unavailable`) sambil membawa lirik tanpa timestamp lewat
   `setPlainOnly(text, label)` (cache: `{ cues: [], label, plain }`). Router mencatatnya saat provider itu menyerah
   (`_plainFound`), karena provider yang tidak dipakai lagi akan `reset()`. Lirik itu baru diberikan sebagai
   `plainText` / `plainSourceName` setelah jenjang selesai (provider yang dipakai sudah ada di `_exhausted`), supaya
   tidak muncul sekejap saat router pindah ke provider berikutnya. Kalau ada beberapa, yang dipakai adalah lirik dari
   provider dengan prioritas tertinggi. Popup menampilkannya sebagai teks biasa (footer: "sc: … · unsynced"), sedangkan
   panel tetap kosong karena tidak ada waktu untuk diikuti.

Langkah menambah service:
1. Buat `ui/providers/NamaProvider.qml`. Kerangka minimalnya ada di komentar atas `TranscriptProvider.qml`,
   dan contoh lengkapnya adalah `YouTubeProvider.qml`. Logika murni (parsing, pemilihan track) taruh di
   `code/*.js` supaya bisa dites tanpa jaringan.
2. Daftarkan di `providers: [...]` pada `TranscriptSource` di `main.qml`, sesuai prioritasnya.
3. Tambahkan test: logika di `code/*.js`, dan routing dengan provider palsu (lihat `tests/tst_providers.qml`).

Kandidat berikutnya:

- File `.srt`/`.vtt`/`.lrc` di samping file media (dari `xesam:url`)
- LRCLIB untuk player musik lain (Elisa, YouTube Music, dan lain-lain): cukup tambahkan nama ke `players`/`urlPrefixes`
- Video YouTube tanpa URL (tanpa PBI): cari video berdasarkan judul + durasi
- Speech-to-text lokal (whisper.cpp) sebagai daemon terpisah, yang mengirim cue lewat D-Bus. Untuk ini
  mungkin perlu plugin C++ kecil, atau `Plasma5Support.DataSource` sebagai jembatan.
