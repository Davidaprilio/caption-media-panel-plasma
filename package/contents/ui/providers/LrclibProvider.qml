import QtQuick
import "../../code/lrclib.js" as Lrclib

// Synced lyrics from LRCLIB for music players: Spotify, and YouTube Music
// (listed after YouTubeProvider, so it is only asked when the video has no
// captions).
// At most two requests per track: an exact lookup (title, artist, album,
// duration), then a search when that finds nothing synced. Misses are
// cached too, so replaying a song without lyrics does not ask again.
//
// /api/get answers 503 for tracks it has to look up elsewhere when LRCLIB is
// busy, so a 503 there goes straight to the (cheap) search instead of waiting.
TranscriptProvider {
    id: provider

    // Matched case-insensitively against the MPRIS identity and desktop entry.
    property var players: ["spotify"]
    // Browser media (via Plasma Browser Integration) from these pages.
    property var urlPrefixes: ["https://open.spotify.com/", "https://music.youtube.com/"]

    readonly property string _key: media ? media.artist + "\u001f" + media.track + "\u001f" + media.album : ""
    // The track to load: none while another provider is in use.
    readonly property string _wanted: active ? _key : ""

    providerId: "lrclib"
    displayName: "LRCLIB"
    canHandle: media !== null && media.track !== "" && media.artist !== ""
        && Lrclib.matchesPlayer(media.identity, media.desktopEntry, media.url, players, urlPrefixes)

    // kmpris updates metadata one field at a time (the title changes before
    // the length), so wait until the change has settled.
    on_WantedChanged: Qt.callLater(_loadWanted)

    function _loadWanted() {
        load(_wanted);
    }

    property HttpClient http: HttpClient {
        headers: ({ "User-Agent": Lrclib.USER_AGENT })
        // LRCLIB answers 503 + Retry-After when its queue is full.
        retries: 2
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
        http.get(Lrclib.getUrl(q), (ok, text, httpStatus) => {
            const record = ok ? _parse(text) : null;
            if (Lrclib.isUsable(record)) {
                _finish(key, record, q);
            } else if (record || httpStatus === 404 || httpStatus === 503 || httpStatus === 429) {
                // Not found, only unsynced lyrics, or busy: maybe search has it.
                _search(key, q);
            } else {
                setUnavailable("LRCLIB request failed (HTTP " + httpStatus + ")");
            }
        }, 0);
    }

    function _search(key, q) {
        http.get(Lrclib.searchUrl(q), (ok, text, httpStatus) => {
            const results = ok ? _parse(text) : null;
            if (!Array.isArray(results)) {
                // Failed, not a miss: don't cache, the next play asks again.
                setUnavailable("LRCLIB search failed (HTTP " + httpStatus + ")");
                return;
            }
            const record = Lrclib.pickResult(results, q.durationS);
            if (record) {
                _finish(key, record, q);
                return;
            }
            remember(key, { cues: [], label: displayName });
            setUnavailable("no synced lyrics for " + q.artist + " - " + q.track + " (" + results.length + " search results)");
        });
    }

    function _finish(key, record, q) {
        const newCues = Lrclib.recordToCues(record, q.durationS * 1000);
        remember(key, { cues: newCues, label: displayName });
        setReady(newCues, displayName);
    }

    function _parse(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }
}
