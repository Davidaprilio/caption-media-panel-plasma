# Caption Media Panel

Widget KDE Plasma 6 untuk panel yang menampilkan caption/transcript dari media yang sedang diputar
(semua player MPRIS: browser, Spotify, VLC, dan lain-lain).

**Status:**
- **YouTube** di browser memakai transkrip asli dari YouTube (caption manual atau auto-generated).
  Syaratnya: [Plasma Browser Integration](https://community.kde.org/Plasma/Browser_Integration) beserta ekstensi browser-nya terpasang.
- **Media lain** masih memakai transcript **dummy** yang mengikuti posisi player. Ini bisa dimatikan di pengaturan.

Lihat [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Fitur

- **Mode lyric**: baris bergeser naik seperti lirik di aplikasi musik. Jumlah baris 1–5 (default 1).
- **Mode marquee**: satu baris yang bergeser hanya kalau teks tidak muat.
- **Lebar** auto (mengikuti baris terpanjang, dengan batas maksimum) atau manual (px).
- **Popup** berisi transcript lengkap: baris aktif di-highlight dan auto-scroll. Klik baris untuk seek player.
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
```

`fake_mpris_player.py` memakai Python sistem (`/usr/bin/python3`), karena butuh `python-dbus` dan `python-gobject`.
