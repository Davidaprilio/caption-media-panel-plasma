# Caption Media Panel

[English](README.md) · **Bahasa Indonesia**

Widget panel KDE Plasma 6 yang menampilkan caption dan lirik tersinkron dari media yang sedang diputar
(semua player MPRIS: browser, Spotify, VLC, …).

**Sumber teksnya:**
- **YouTube** di browser: caption bawaan video, baik manual maupun auto-generated.
  Butuh Plasma Browser Integration beserta ekstensi browser-nya (lihat [Media di browser](#media-di-browser)).
- **Spotify** (aplikasi desktop maupun Spotify Web) dan **YouTube Music**: lirik tersinkron dari NetEase Cloud Music.
  Kalau ada versi **romanisasi**, versi itu yang dipakai (misalnya romaji untuk lagu Jepang); kalau tidak, teks
  aslinya. Kalau NetEase tidak punya liriknya: lirik tersinkron dari YouTube Music (Musixmatch / LyricFind), lalu
  [LRCLIB](https://lrclib.net), lalu (khusus YouTube Music) caption videonya. Kalau tidak ada satu pun sumber yang
  tersinkron tetapi ada lirik **tanpa timestamp** (YouTube Music atau LRCLIB), lirik itu tampil sebagai teks biasa di
  popup, dan panel tetap kosong.
- **Media lain**: secara default tidak ada teks. Untuk pengujian, transcript **dummy** yang mengikuti posisi player bisa
  dinyalakan di pengaturan (Testing).

Cara kerjanya dijelaskan di [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Fitur

- **Mode lyric**: baris bergeser naik seperti di aplikasi musik. Jumlah baris yang terlihat 1–5 (default 1).
- **Mode marquee**: ticker satu baris. Baris berikutnya selalu menunggu di kanan baris aktif dengan warna redup, dalam
  slot maksimal 100 px; teks yang lebih panjang memudar. Saat waktunya tiba, baris itu bergeser ke kiri menggantikan
  baris aktif, bagian yang memudar ikut terbuka, dan baris sesudahnya masuk dari kanan. Baris yang terlalu panjang
  untuk panel digulir selama durasinya.
- **Perataan teks**: kiri, tengah, atau kanan. Di mode marquee, yang diratakan adalah baris aktif ditambah slot 100 px,
  sehingga posisi baris aktif tidak bergantung pada panjang baris berikutnya.
- **Lebar**: otomatis (baris terpanjang, atau baris terpanjang + slot baris berikutnya di mode marquee, dibatasi
  "Maximum automatic width") atau tetap dalam piksel.
- Saat tidak ada media atau tidak ada teks, area widget di panel dibiarkan kosong.
- **Popup**: artwork, judul dan artis, tombol previous / play-pause / next, serta transcript lengkap dengan baris aktif
  yang di-highlight dan auto-scroll; klik baris untuk seek. Footer menampilkan sumber yang dipakai, dan bisa memilih
  sumber lain yang **punya lirik** untuk lagu itu (dicek selama popup terbuka). Lirik tanpa sinkron ditampilkan sebagai
  teks biasa yang bisa di-scroll, dengan tanda "unsynced" di footer. Kalau daftar digulir sendiri, auto-scroll berhenti
  dan muncul tombol **Follow lyrics** untuk kembali ke baris yang sedang diputar (scroll halus) dan mengikutinya lagi.
- **Equalizer** di belakang caption di panel dan di belakang judul popup (masing-masing bisa dimatikan). Kalau
  [cava](https://github.com/karlstav/cava) dan modul QML Qt WebSockets terpasang (lihat [Kebutuhan](#kebutuhan)), bar mengikuti suara yang keluar dari
  speaker; tanpa cava, bar bergerak dekoratif. Keduanya memakai satu sumber audio yang sama. Warna (aksen tema atau
  warna pilihan) dan opacity (panel dan popup terpisah) bisa diatur.
- **Mode ambient** di popup: artwork di-blur dan memancar dari belakang thumbnail ke seluruh header (bisa dimatikan).
- Panel vertikal: widget tampil sebagai ikon, transcript dibaca lewat popup.
- *Demo mode* (opsional): memutar transcript dummy dengan jam lokal kalau tidak ada player.

## Kebutuhan

- KDE Plasma 6 (dikembangkan di Plasma 6.7 / Qt 6.11, Wayland; juga berjalan di Plasma 6.6 dengan X11).
- `curl` (request ke NetEase) dan `busctl` (systemd; membaca URL media di browser).
- Untuk media di browser: Plasma Browser Integration beserta ekstensi browser-nya, lihat [Media di browser](#media-di-browser).
- Opsional, untuk equalizer yang mengikuti audio: `cava`, `python3` (cukup library standar), dan modul QML Qt
  WebSockets. Tanpa itu bar bergerak dekoratif, dan halaman pengaturan menyebutkan apa yang belum terpasang.

| Distribusi | Equalizer live (opsional) |
|---|---|
| Debian, Ubuntu, Kubuntu | `sudo apt install cava qml6-module-qtwebsockets` |
| Arch, CachyOS, Manjaro | `sudo pacman -S cava qt6-websockets` |
| Fedora | `sudo dnf install cava qt6-qtwebsockets` |

Widget-nya sendiri murni QML: tanpa proses build dan tanpa plugin native yang berjalan di dalam plasmashell.

## Media di browser

Player media bawaan browser hampir tidak memberi tahu Plasma apa pun selain "a site is playing media". Lirik dan caption
butuh informasi halaman dan lagunya, dan itu hanya diberikan oleh
[Plasma Browser Integration](https://community.kde.org/Plasma/Browser_Integration). Tanpa itu, popup menampilkan
"Can't tell what … is playing".

1. Pasang paket sistem `plasma-browser-integration` (namanya sama di Debian/Ubuntu, Arch, dan Fedora).
2. Pasang ekstensi **Plasma Integration**:
   [Chrome Web Store](https://chromewebstore.google.com/detail/plasma-integration/cimiefiiaegbelhefglklhhakcgmhkai)
   (Chrome, Chromium, Brave, Vivaldi, …),
   [Edge Add-ons](https://microsoftedge.microsoft.com/addons/detail/plasma-integration/dnnckbejblnejeabhcmhklcaljjpdjeh),
   atau [Firefox Add-ons](https://addons.mozilla.org/firefox/addon/plasma-integration/).
3. Paket itu hanya mendaftarkan native messaging host untuk sebagian browser (tergantung distribusinya; di Ubuntu
   misalnya hanya untuk Chrome). Kalau ekstensinya tidak bisa terhubung ke Plasma di browser berbasis Chromium lain,
   tautkan host-nya ke folder browser tersebut, lalu restart browser:

   ```fish
   # Microsoft Edge; untuk Brave pakai ~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts,
   # Vivaldi ~/.config/vivaldi/NativeMessagingHosts, Chromium ~/.config/chromium/NativeMessagingHosts
   mkdir -p ~/.config/microsoft-edge/NativeMessagingHosts
   ln -s /etc/opt/chrome/native-messaging-hosts/org.kde.plasma.browser_integration.json \
       ~/.config/microsoft-edge/NativeMessagingHosts/
   ```

## Instalasi dan pengembangan

```fish
./scripts/dev.sh install    # pasang / upgrade untuk user ini
./scripts/dev.sh restart    # restart plasmashell supaya perubahan QML terbaca
./scripts/dev.sh reload     # install + restart
./scripts/dev.sh view       # jalankan di plasmoidviewer (perlu: sudo pacman -S plasma-sdk)
./scripts/dev.sh lint       # qmllint
./scripts/dev.sh package    # buat dist/caption-media-panel-<versi>.plasmoid (untuk diunggah ke KDE Store)
./scripts/dev.sh remove     # uninstall
```

Setelah install: klik kanan panel → **Add Widgets…** → cari "Caption Media Panel".
File `.plasmoid` juga bisa dipasang dengan `kpackagetool6 -t Plasma/Applet -i <file>.plasmoid`.

## Test

```fish
# unit test (headless, tanpa jaringan: provider dites dengan bentuk respons yang direkam)
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests

# fake player MPRIS untuk mencoba widget tanpa media sungguhan
tests/fake_mpris_player.py --length 600 --script "10:pause,13:play,16:seek=120,25:quit"

# berpura-pura menjadi Spotify (lirik dari NetEase / YouTube Music / LRCLIB)
tests/fake_mpris_player.py --identity Spotify --desktop-entry spotify \
    --title blue --artist "yung kai" --album blue --length 214
```

`fake_mpris_player.py` memakai Python sistem (`/usr/bin/python3`), karena butuh `python-dbus` dan `python-gobject`.

## Catatan tentang sumber lirik

Caption YouTube, lirik YouTube Music, dan lirik NetEase diambil lewat API tidak resmi (tanpa key, tanpa login). API itu
bisa berubah sewaktu-waktu; kalau salah satunya berhenti bekerja, widget beralih ke sumber berikutnya, sampai LRCLIB.
