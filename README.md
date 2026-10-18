# Caption Media Panel

Widget KDE Plasma 6 untuk panel yang menampilkan caption/transcript dari media yang sedang diputar
(semua player MPRIS: browser, Spotify, VLC, dan lain-lain).

**Status:**
- **YouTube** di browser memakai transkrip asli dari YouTube (caption manual atau auto-generated).
  Syaratnya: [Plasma Browser Integration](https://community.kde.org/Plasma/Browser_Integration) beserta ekstensi browser-nya terpasang.
- **Spotify** (aplikasi desktop maupun Spotify Web) memakai lirik tersinkron dari [LRCLIB](https://lrclib.net).
- **YouTube Music** memakai caption YouTube kalau ada. Kalau tidak ada, widget otomatis beralih ke lirik LRCLIB.
- **Media lain** masih memakai transcript **dummy** yang mengikuti posisi player. Ini bisa dimatikan di pengaturan.

Lihat [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Fitur

- **Mode lyric**: baris bergeser naik seperti lirik di aplikasi musik. Jumlah baris 1–5 (default 1).
- **Mode marquee**: satu baris bergaya ticker. Baris berikutnya selalu terlihat di sisi kanan baris aktif dengan warna
  redup, dalam slot maksimal 200 px; teks yang lebih panjang memudar dengan gradasi. Saat waktunya tiba, baris itu
  bergeser ke kiri menggantikan baris aktif, bagian yang memudar ikut terbuka, dan lirik sesudahnya masuk dari kanan
  ke slot yang ditinggalkan. Baris yang terlalu panjang digulir
  dulu selama durasinya.
- **Perataan teks**: kiri, tengah, atau kanan. Di mode marquee, yang diratakan adalah baris aktif ditambah slot 200 px,
  sehingga posisi baris aktif tidak bergantung pada panjang baris berikutnya.
- **Lebar auto** mengikuti baris terpanjang (lyric), atau baris terpanjang + slot baris berikutnya (marquee), dibatasi
  "Maximum automatic width".
- Saat tidak ada media atau tidak ada teks, area widget di panel dibiarkan kosong.
- **Lebar** auto (mengikuti baris terpanjang, dengan batas maksimum) atau manual (px).
- **Popup** berisi thumbnail/album art, judul dan artis, tombol previous / play-pause / next, serta transcript lengkap:
  baris aktif di-highlight dan auto-scroll. Klik baris untuk seek player.
- **Equalizer animasi** di belakang judul popup (dekoratif, bukan level audio sungguhan). Bisa dimatikan di pengaturan.
- Panel vertikal: widget tampil sebagai ikon, transcript dibaca lewat popup.
- *Demo mode* (opsional): memutar transcript dummy dengan jam lokal kalau tidak ada player.

## Instalasi dan pengembangan

```fish
./scripts/dev.sh install    # pasang / upgrade untuk user ini
./scripts/dev.sh restart    # restart plasmashell supaya perubahan QML terbaca
./scripts/dev.sh reload     # install + restart
./scripts/dev.sh view       # jalankan di plasmoidviewer (perlu: sudo pacman -S plasma-sdk)
./scripts/dev.sh lint       # qmllint
./scripts/dev.sh remove     # uninstall
```

Setelah install: klik kanan panel → **Add Widgets…** → cari "Caption Media Panel".

## Test

```fish
# unit test CueClock + helper (headless)
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests

# fake player MPRIS untuk mencoba widget tanpa media sungguhan
tests/fake_mpris_player.py --length 600 --script "10:pause,13:play,16:seek=120,25:quit"

# berpura-pura menjadi Spotify (lirik dari LRCLIB)
tests/fake_mpris_player.py --identity Spotify --desktop-entry spotify \
    --title blue --artist "yung kai" --album blue --length 214
```

`fake_mpris_player.py` memakai Python sistem (`/usr/bin/python3`), karena butuh `python-dbus` dan `python-gobject`.
