# Caption Media Panel

**English** · [Bahasa Indonesia](README.id.md)

A KDE Plasma 6 panel widget that shows synced captions and lyrics for whatever is playing
(any MPRIS player: browsers, Spotify, VLC, …).

**Where the text comes from:**
- **YouTube** in a browser: the video's own captions (manual or auto-generated).
  Needs Plasma Browser Integration and its browser extension (see [Browser media](#browser-media)).
- **Spotify** (desktop app or Spotify Web) and **YouTube Music**: synced lyrics from NetEase Cloud Music, using the
  **romanized** version when there is one (e.g. romaji for Japanese songs) and the original text otherwise. Without
  NetEase lyrics: synced lyrics from YouTube Music (Musixmatch / LyricFind), then [LRCLIB](https://lrclib.net), then
  (YouTube Music only) the video's captions. When no source has synced lyrics but one has **unsynced** lyrics
  (YouTube Music or LRCLIB), they are shown as plain text in the popup; the panel stays empty.
- **Other media**: nothing by default. For testing, a **dummy** transcript that follows the player's position can be
  turned on in the settings (Testing).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (Indonesian) for how it works.

## Features

- **Lyric mode**: lines move up like in music apps; 1–5 visible lines (default 1).
- **Marquee mode**: a one-line ticker. The next line always waits on the right of the active one, muted, in a slot of at
  most 100 px whose overflow fades out. When its time comes it slides left into the active place, its faded tail is
  revealed, and the line after it rides in from the right. Lines too long for the panel scroll within their duration.
- **Text alignment**: left, center or right. In marquee mode the active line plus the 100 px slot is aligned, so the
  active line does not move with the length of the next one.
- **Width**: automatic (longest line, or longest line + next-line slot in marquee mode, capped by
  "Maximum automatic width") or fixed in pixels.
- With no media or no text, the widget's area in the panel stays empty.
- **Popup**: artwork, title and artist, previous / play-pause / next buttons, and the whole transcript with the active
  line highlighted and auto-scrolled; click a line to seek. The footer shows the source in use and lets you pick any
  other source that **has lyrics** for the current track (checked while the popup is open). Unsynced lyrics are shown
  as scrollable plain text, marked "unsynced" in the footer. Scrolling the list yourself pauses auto-scroll; a
  **Follow lyrics** button glides back to the current line and follows it again.
- **Equalizer** behind the panel caption and behind the popup title (each can be turned off). With
  [cava](https://github.com/karlstav/cava) and the Qt WebSockets QML module installed (see [Requirements](#requirements)) the bars follow the sound coming out of
  the speakers; without it they move decoratively. Both share one audio source. Color (theme accent or your own) and
  opacity (panel and popup separately) are configurable.
- **Ambient mode** in the popup: the artwork, blurred, glows out from behind the thumbnail across the header
  (can be turned off).
- Vertical panels: the widget shows an icon; read the transcript in the popup.
- Optional *demo mode*: plays the dummy transcript on a local clock when no player is running.

## Requirements

- KDE Plasma 6 (developed on Plasma 6.7 / Qt 6.11, Wayland; also runs on Plasma 6.6 with X11).
- `curl` (NetEase requests) and `busctl` (systemd; reads browser media URLs).
- For browser media: Plasma Browser Integration and its browser extension, see [Browser media](#browser-media).
- Optional, for an equalizer that follows the audio: `cava`, `python3` (only the standard library) and the Qt WebSockets
  QML module. Without them the bars move decoratively, and the settings page says what is missing.

| Distribution | Live equalizer (optional) |
|---|---|
| Debian, Ubuntu, Kubuntu | `sudo apt install cava qml6-module-qtwebsockets` |
| Arch, CachyOS, Manjaro | `sudo pacman -S cava qt6-websockets` |
| Fedora | `sudo dnf install cava qt6-qtwebsockets` |

The widget itself is pure QML: no build step and no native plugin running inside plasmashell.

## Browser media

The browser's own media player tells Plasma little more than "a site is playing media". Lyrics and captions need to
know the page and the song, which only [Plasma Browser Integration](https://community.kde.org/Plasma/Browser_Integration)
provides. Without it the popup says "Can't tell what … is playing".

1. Install the system package `plasma-browser-integration` (same name on Debian/Ubuntu, Arch and Fedora).
2. Install the **Plasma Integration** extension:
   [Chrome Web Store](https://chromewebstore.google.com/detail/plasma-integration/cimiefiiaegbelhefglklhhakcgmhkai)
   (Chrome, Chromium, Brave, Vivaldi, …),
   [Edge Add-ons](https://microsoftedge.microsoft.com/addons/detail/plasma-integration/dnnckbejblnejeabhcmhklcaljjpdjeh),
   or [Firefox Add-ons](https://addons.mozilla.org/firefox/addon/plasma-integration/).
3. The package registers its native messaging host only for some browsers (which ones depends on the distribution:
   Ubuntu only for Chrome, for example). If the extension cannot reach Plasma in another Chromium-based browser, link
   the host into that browser's folder and restart the browser:

   ```fish
   # Microsoft Edge; for Brave use ~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts,
   # for Vivaldi ~/.config/vivaldi/NativeMessagingHosts, for Chromium ~/.config/chromium/NativeMessagingHosts
   mkdir -p ~/.config/microsoft-edge/NativeMessagingHosts
   ln -s /etc/opt/chrome/native-messaging-hosts/org.kde.plasma.browser_integration.json \
       ~/.config/microsoft-edge/NativeMessagingHosts/
   ```

## Install and develop

```fish
./scripts/dev.sh install    # install / upgrade for the current user
./scripts/dev.sh restart    # restart plasmashell so the panel picks up QML changes
./scripts/dev.sh reload     # install + restart
./scripts/dev.sh view       # run in plasmoidviewer (needs: sudo pacman -S plasma-sdk)
./scripts/dev.sh lint       # qmllint
./scripts/dev.sh package    # build dist/caption-media-panel-<version>.plasmoid (KDE Store upload)
./scripts/dev.sh remove     # uninstall
```

After installing: right-click the panel → **Add Widgets…** → search for "Caption Media Panel".
A `.plasmoid` file can also be installed with `kpackagetool6 -t Plasma/Applet -i <file>.plasmoid`.

## Tests

```fish
# unit tests (headless, no network: providers are tested against recorded response shapes)
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests

# a fake MPRIS player, to try the widget without real media
tests/fake_mpris_player.py --length 600 --script "10:pause,13:play,16:seek=120,25:quit"

# pretend to be Spotify (lyrics from NetEase / YouTube Music / LRCLIB)
tests/fake_mpris_player.py --identity Spotify --desktop-entry spotify \
    --title blue --artist "yung kai" --album blue --length 214
```

`fake_mpris_player.py` uses the system Python (`/usr/bin/python3`): it needs `python-dbus` and `python-gobject`.

## Note on the lyrics sources

YouTube captions, YouTube Music lyrics and NetEase lyrics come from unofficial APIs (no key, no login). They can change
at any time; when one stops working, the widget falls back to the next source, down to LRCLIB.
