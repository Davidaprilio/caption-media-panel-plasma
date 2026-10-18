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
                   position, track,    currentIndex, active    YouTubeProvider  (URL YouTube)
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
| `ui/MediaSource.qml` | Adapter **satu-satunya** ke `org.kde.plasma.private.mpris` (API private Plasma). Kalau API itu berubah, cukup file ini yang diubah. |
| `ui/CueClock.qml` | Menentukan cue yang sedang tampil berdasarkan posisi player. |
| `ui/TranscriptSource.qml` | Router generik: memilih provider untuk media saat ini, lalu meneruskan output-nya. Daftar provider diisi di `main.qml`. |
| `ui/providers/TranscriptProvider.qml` | **Interface** semua service transkrip (lihat "Menambah service transkrip"). |
| `ui/providers/HttpClient.qml` | HTTP async bersama untuk provider: timeout, pembatalan, dan pengabaian jawaban basi. |
| `ui/providers/YouTubeProvider.qml`, `code/youtube.js` | Transkrip asli YouTube (lihat di bawah). |
| `ui/providers/DummyProvider.qml` | Provider fallback berisi teks dummy. |
| `code/cues.js` | Binary search, batas cue berikutnya, dan helper. |
| `code/dummyTranscript.js` | Teks dummy. |
| `ui/LyricView.qml`, `ui/MarqueeView.qml` | Tampilan di panel. |
| `ui/FullRepresentation.qml` | Popup transcript. Baru dibuat saat pertama kali dibuka. |

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

## Lebar di panel

- **Auto**: lebar baris terpanjang di transcript, dibatasi `maxAutoWidth`. Nilainya dihitung sekali
  per transcript dengan `TextMetrics`, hanya untuk teks unik. Akibatnya, pergantian baris tidak memicu relayout
  panel, sehingga applet lain tidak ikut bergeser.
- **Manual**: lebar tetap dalam px.

Ukuran font otomatis mengecil kalau `N baris × tinggi baris` lebih besar dari tinggi panel.

## Performa (hasil ukur)

- Saat media diputar: 0 tick CPU dalam 20 detik (diukur di `plasmawindowed`, kurang dari 10 ms CPU).
- Saat di-pause atau idle: tidak ada timer dan tidak ada animasi.
- Animasi hanya berjalan sekitar 250 ms per pergantian baris (mode lyric), atau selama teks marquee overflow.
  Animasi otomatis mati kalau animasi Plasma dimatikan (`Kirigami.Units.longDuration == 0`).

## Menambah service transkrip

Setiap service adalah turunan dari `providers/TranscriptProvider.qml`:

| Bagian | Properti | Siapa yang mengisi |
|---|---|---|
| Deskripsi | `providerId`, `displayName`, `fallback`, `enabled` | provider (`enabled` boleh dari config) |
| Input | `media` (MediaSource), `languages`, `active` | `TranscriptSource` |
| Keputusan | `canHandle`: binding murah, "apakah media ini bisa saya layani?" | provider |
| Output | `cues`, `status` (enum `TranscriptProvider.Idle/Loading/Ready/Unavailable`), `sourceName` | provider, lewat `setLoading()`, `setReady()`, `setUnavailable()`, `reset()` |
| Helper | `cached()` / `remember()` (cache memori), `HttpClient` | dipakai provider |

Aturan router (`TranscriptSource`):
1. Provider pertama (urut daftar) yang `enabled`, bukan `fallback`, dan `canHandle` akan dipakai.
2. Kalau tidak ada, dipakai fallback pertama yang `enabled`. Selama URL media masih dicari
   (`media.urlPending`), fallback ditahan dulu supaya tidak sempat muncul sekejap.
3. Hanya provider yang `active` boleh bekerja (request jaringan, proses). Provider lain memanggil `reset()`.

Langkah menambah service:
1. Buat `ui/providers/NamaProvider.qml`. Kerangka minimalnya ada di komentar atas `TranscriptProvider.qml`,
   dan contoh lengkapnya adalah `YouTubeProvider.qml`. Logika murni (parsing, pemilihan track) taruh di
   `code/*.js` supaya bisa dites tanpa jaringan.
2. Daftarkan di `providers: [...]` pada `TranscriptSource` di `main.qml`, sesuai prioritasnya.
3. Tambahkan test: logika di `code/*.js`, dan routing dengan provider palsu (lihat `tests/tst_providers.qml`).

Kandidat berikutnya:

- File `.srt`/`.vtt`/`.lrc` di samping file media (dari `xesam:url`)
- Layanan lirik (misalnya lrclib) untuk musik
- Video YouTube tanpa URL (tanpa PBI): cari video berdasarkan judul + durasi
- Speech-to-text lokal (whisper.cpp) sebagai daemon terpisah, yang mengirim cue lewat D-Bus. Untuk ini
  mungkin perlu plugin C++ kecil, atau `Plasma5Support.DataSource` sebagai jembatan.
