import QtQuick
import "../../code/lrclib.js" as Lrclib
import "../../code/ytmusic.js" as YTMusic

// Synced lyrics from YouTube Music (Musixmatch / LyricFind) for the same music
// players as NetEase and LRCLIB (Spotify, YouTube Music). On YouTube Music the
// playing video is asked first (2 requests); music videos often have only
// plain lyrics, so then, and for Spotify, the song is searched (+1 request).
// Lyrics without timestamps are never used. Misses are cached.
TranscriptProvider {
    id: provider

    // Matched case-insensitively against the MPRIS identity and desktop entry.
    property var players: ["spotify"]
    // Browser media (via Plasma Browser Integration) from these pages.
    property var urlPrefixes: ["https://open.spotify.com/", "https://music.youtube.com/"]

    readonly property string _key: media ? [media.artist, media.track, media.album, media.url].join("\u001f") : ""
    // The track to load: none while another provider is in use (unless probing).
    readonly property string _wanted: active || probing ? _key : ""

    providerId: "ytmusic"
    // Short: it is shown in the popup footer and its source picker.
    displayName: "YT Music"
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

    property HttpClient http: HttpClient {}

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
        const videoId = YTMusic.videoIdFromUrl(media.url);
        if (videoId) {
            _fetchLyrics(key, q, videoId, () => _search(key, q, videoId));
        } else {
            _search(key, q, "");
        }
    }

    // next + browse for one video; `orElse` runs when it has no synced lyrics.
    function _fetchLyrics(key, q, videoId, orElse) {
        http.postJson(YTMusic.NEXT_URL, YTMusic.nextRequest(videoId), (ok, text, httpStatus) => {
            if (!ok) {
                _failed("next", httpStatus);
                return;
            }
            const browseId = YTMusic.lyricsBrowseId(_parse(text));
            if (!browseId) {
                orElse();
                return;
            }
            http.postJson(YTMusic.BROWSE_URL, YTMusic.browseRequest(browseId), (ok2, text2, httpStatus2) => {
                if (!ok2) {
                    _failed("browse", httpStatus2);
                    return;
                }
                const result = YTMusic.timedCues(_parse(text2));
                if (result) {
                    _finish(key, result);
                } else {
                    orElse();
                }
            });
        });
    }

    function _search(key, q, excludeVideoId) {
        http.postJson(YTMusic.SEARCH_URL, YTMusic.searchRequest(q), (ok, text, httpStatus) => {
            if (!ok) {
                _failed("search", httpStatus);
                return;
            }
            const candidates = YTMusic.searchCandidates(_parse(text), q).filter(song => song.videoId !== excludeVideoId);
            if (candidates.length === 0) {
                _miss(key, "no matching song for " + q.artist + " - " + q.track);
                return;
            }
            _fetchLyrics(key, q, candidates[0].videoId, () => _miss(key, "no synced lyrics for " + q.artist + " - " + q.track));
        });
    }

    function _finish(key, result) {
        // A source label like "YouTube · English", not translated UI text.
        const label = displayName + (result.source ? " · " + result.source : "");
        remember(key, { cues: result.cues, label: label });
        setReady(result.cues, label);
    }

    function _miss(key, reason) {
        remember(key, { cues: [], label: displayName });
        setUnavailable(reason);
    }

    // Failed, not a miss: not cached, the next play asks again.
    function _failed(step, httpStatus) {
        setUnavailable("YouTube Music " + step + " request failed (HTTP " + httpStatus + ")");
    }

    function _parse(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }
}
