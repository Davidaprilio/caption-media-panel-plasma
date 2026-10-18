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
 MPRIS (D-Bus) ──► MediaSource.qml ──► CueClock.qml ◄── Provider (DummyProvider.qml)
                   playing, rate,      posisi interpolasi,   cues[] {start,end,text}
                   position, track     currentIndex, active
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
| `ui/DummyProvider.qml` | Provider sementara. Kontraknya dijelaskan di komentar atas file. |
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

## Menambah sumber transcript nanti

Buat provider baru dengan kontrak yang sama seperti `DummyProvider.qml`:

- input: `trackKey`, `title`, `artist`, `lengthMs`
- output: `cues` (array terurut dan tidak tumpang tindih), `status`, `sourceName`

Lalu ganti `DummyProvider` di `main.qml`. Beberapa kandidat:

- File `.srt`/`.vtt`/`.lrc` di samping file media (dari `xesam:url`)
- Layanan lirik (misalnya lrclib) untuk musik
- Speech-to-text lokal (whisper.cpp) sebagai daemon terpisah, yang mengirim cue lewat D-Bus. Untuk ini
  mungkin perlu plugin C++ kecil, atau `Plasma5Support.DataSource` sebagai jembatan.
