import QtQuick
import "../../code/lrclib.js" as Lrclib
import "../../code/netease.js" as Netease

// Synced lyrics from NetEase Cloud Music for the same music players as
// LRCLIB (Spotify, YouTube Music). Prefers NetEase's synced romanization
// (romaji, ...) when it has one, else the original lyrics. Two requests per
// track: search, then lyrics. Misses are cached like in LrclibProvider.
TranscriptProvider {
    id: provider

    // Matched case-insensitively against the MPRIS identity and desktop entry.
    property var players: ["spotify"]
    // Browser media (via Plasma Browser Integration) from these pages.
    property var urlPrefixes: ["https://open.spotify.com/", "https://music.youtube.com/"]
    // Romanized lines where NetEase has them, original lines otherwise.
    property bool preferRomanized: true

    readonly property string _key: media ? [media.artist, media.track, media.album, preferRomanized].join("\u001f") : ""
    // The track to load: none while another provider is in use (unless probing).
    readonly property string _wanted: active || probing ? _key : ""

    providerId: "netease"
    displayName: "NetEase"
    canHandle: media !== null && media.track !== "" && media.artist !== ""
        && Lrclib.matchesPlayer(media.identity, media.desktopEntry, media.url, players, urlPrefixes)

    // kmpris updates metadata one field at a time; wait until it has settled.
    // The previous track's lyrics go at once, though.
    on_WantedChanged: {
        if (_wanted) {
            setLoading();
        }
        Qt.callLater(_loadWanted);
    }

    function _loadWanted() {
        load(_wanted);
    }

    property HttpClient http: HttpClient {
        headers: ({ "User-Agent": Lrclib.USER_AGENT })
        retries: 1
        // NetEase answers with unrelated songs once its tracking cookie comes back.
        cookieless: true
    }

    function load(key) {
        http.cancel();
        if (!key) {
            reset();
            return;
        }
        const hit = cached(key);
        if (hit) {
            setReady(hit.cues, hit.label);
            return;
        }
        setLoading();
        const q = Lrclib.query(media.track, media.artist, media.album, media.lengthMs);
        http.get(Netease.searchUrl(q), (ok, text, httpStatus) => {
            const response = ok ? _parse(text) : null;
            if (!response || response.code !== 200) {
                // Failed, not a miss: don't cache, the next play asks again.
                setUnavailable("NetEase search failed (HTTP " + httpStatus + ")");
                return;
            }
            // Several releases of a song are listed; the best one may have no
            // synced lyrics, or no romanization where another one has.
            const candidates = Netease.rankSongs(response, q).slice(0, 4);
            if (candidates.length === 0) {
                _miss(key, "no matching song for " + q.artist + " - " + q.track);
                return;
            }
            _fetchLyrics(key, candidates, 0, null, q);
        });
    }

    // Tries the candidates in order: the first with synced lyrics (and, when
    // preferred, a romanization) wins; without a romanization anywhere, the
    // first one's original lyrics are used.
    function _fetchLyrics(key, candidates, index, fallback, q) {
        const song = candidates[index];
        http.get(Netease.lyricUrl(song.id), (ok, text, httpStatus) => {
            const response = ok ? _parse(text) : null;
            const result = response && response.code === 200 ? Netease.buildCues(response, q.durationS * 1000, preferRomanized) : null;
            const usable = result && result.cues.length > 0 ? result : null;
            if (usable && (usable.romanized || !preferRomanized)) {
                _finish(key, usable);
            } else if (index + 1 < candidates.length) {
                _fetchLyrics(key, candidates, index + 1, fallback || usable, q);
            } else if (fallback || usable) {
                _finish(key, fallback || usable);
            } else if (!response) {
                setUnavailable("NetEase lyrics request failed (HTTP " + httpStatus + ")");
            } else {
                _miss(key, "no synced lyrics for " + q.artist + " - " + q.track);
            }
        });
    }

    function _finish(key, built) {
        // A source label like "YouTube · English", not translated UI text.
        const label = displayName + (built.romanized ? " · Romanized" : "");
        remember(key, { cues: built.cues, label: label });
        setReady(built.cues, label);
    }

    function _miss(key, reason) {
        remember(key, { cues: [], label: displayName });
        setUnavailable(reason);
    }

    function _parse(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }
}
