.pragma library
.import "lrclib.js" as Lrclib
.import "match.js" as Match
.import "youtube.js" as YouTube

// Synced lyrics from YouTube Music (unofficial InnerTube API, no login), as
// licensed there from Musixmatch and LyricFind.
//
//   next   (web client)    videoId  -> browseId of the song's lyrics page
//   browse (mobile client) browseId -> timedLyricsData with per-line cueRange
//   search (web client, "Songs" filter) -> videoId of a song
//
// Only the mobile client gets timestamps. Music videos often have only plain
// lyrics while the song (audio track) entry has synced ones; plain lyrics are
// never used.

const BASE_URL = "https://music.youtube.com/youtubei/v1/";
const NEXT_URL = BASE_URL + "next?prettyPrint=false";
const BROWSE_URL = BASE_URL + "browse?prettyPrint=false";
const SEARCH_URL = BASE_URL + "search?prettyPrint=false";

// When YouTube stops accepting these, bump the versions here.
const MOBILE_CLIENT = { clientName: "ANDROID_MUSIC", clientVersion: "7.21.50" };
// The web client's version is its build date; today's is always accepted.
function _webClient() {
    const now = new Date();
    const pad = n => (n < 10 ? "0" : "") + n;
    const date = "" + now.getUTCFullYear() + pad(now.getUTCMonth() + 1) + pad(now.getUTCDate());
    return { clientName: "WEB_REMIX", clientVersion: "1." + date + ".01.00", hl: "en" };
}

// The "Songs" filter of YouTube Music search.
const SONGS_FILTER = "EgWKAQIIAWoKEAkQBRAKEAMQBA==";

// Video id of a YouTube Music page URL, "" for anything else.
function videoIdFromUrl(url) {
    return url && String(url).startsWith("https://music.youtube.com/") ? YouTube.videoIdFromUrl(url) : "";
}

function nextRequest(videoId) {
    return { context: { client: _webClient() }, videoId: videoId, isAudioOnly: true };
}

function browseRequest(browseId) {
    return { context: { client: { clientName: MOBILE_CLIENT.clientName, clientVersion: MOBILE_CLIENT.clientVersion, hl: "en" } }, browseId: browseId };
}

function searchRequest(q) {
    return {
        context: { client: _webClient() },
        query: (Lrclib.cleanTitle(q.track) + " " + q.firstArtist).trim(),
        params: SONGS_FILTER,
    };
}

// browseId of the lyrics tab in a next response, "" when the video has none.
function lyricsBrowseId(next) {
    const watchNext = next && next.contents && next.contents.singleColumnMusicWatchNextResultsRenderer;
    const tabbed = watchNext && watchNext.tabbedRenderer && watchNext.tabbedRenderer.watchNextTabbedResultsRenderer;
    const tabs = (tabbed && tabbed.tabs) || [];
    for (let i = 0; i < tabs.length; ++i) {
        const tab = tabs[i].tabRenderer;
        const endpoint = tab && tab.endpoint && tab.endpoint.browseEndpoint;
        const config = endpoint && endpoint.browseEndpointContextSupportedConfigs;
        const pageType = config && config.browseEndpointContextMusicConfig && config.browseEndpointContextMusicConfig.pageType;
        if (pageType === "MUSIC_PAGE_TYPE_TRACK_LYRICS" && endpoint.browseId) {
            return endpoint.browseId;
        }
    }
    return "";
}

function _timedLyrics(browse) {
    const element = browse && browse.contents && browse.contents.elementRenderer;
    const type = element && element.newElement && element.newElement.type;
    const model = type && type.componentType && type.componentType.model;
    return model && model.timedLyricsModel && model.timedLyricsModel.lyricsData;
}

// Browse response -> { cues, source } with every line timed, or null (no
// lyrics, or plain lyrics only).
function timedCues(browse) {
    const data = _timedLyrics(browse);
    const lines = (data && data.timedLyricsData) || [];
    if (lines.length === 0 || !lines.every(line => line.cueRange)) {
        return null;
    }
    const cues = [];
    for (let i = 0; i < lines.length; ++i) {
        const text = String(lines[i].lyricLine || "").replace(/\s+/g, " ").trim();
        const start = parseInt(lines[i].cueRange.startTimeMilliseconds, 10);
        const end = parseInt(lines[i].cueRange.endTimeMilliseconds, 10);
        if (text && end > start) {
            cues.push({ start: start, end: end, text: text });
        }
    }
    // Should already be in order; V4's sort is not stable, hence the index.
    cues.forEach((cue, index) => cue.order = index);
    cues.sort((a, b) => a.start - b.start || a.order - b.order);
    cues.forEach((cue, index) => {
        delete cue.order;
        const next = cues[index + 1];
        if (next && cue.end > next.start) {
            cue.end = next.start;
        }
    });
    const source = String((data && data.sourceMessage) || "").replace(/^Source:\s*/i, "");
    return cues.length > 0 ? { cues: cues, source: source } : null;
}

function _text(column) {
    const renderer = column && column.musicResponsiveListItemFlexColumnRenderer;
    return (renderer && renderer.text && renderer.text.runs) || [];
}

function _durationSeconds(text) {
    const parts = String(text).split(":").map(Number);
    return parts.reduce((total, part) => total * 60 + part, 0);
}

// Songs from a search response that can be the track (match.js score()), best
// first: [{ videoId, title, artists, durationS }].
function searchCandidates(search, q) {
    const found = [];
    (function walk(node) {
        if (Array.isArray(node)) {
            node.forEach(walk);
        } else if (node && typeof node === "object") {
            if (node.musicResponsiveListItemRenderer) {
                found.push(node.musicResponsiveListItemRenderer);
            } else {
                Object.keys(node).forEach(key => walk(node[key]));
            }
        }
    })(search);

    const ranked = [];
    for (let rank = 0; rank < found.length; ++rank) {
        const item = found[rank];
        const videoId = item.playlistItemData && item.playlistItemData.videoId;
        const columns = item.flexColumns || [];
        const titleRuns = _text(columns[0]);
        // Second column: "Artist & Artist • Album • 4:02".
        const groups = [[]];
        _text(columns[1]).forEach(run => {
            if (run.text.trim() === "•") {
                groups.push([]);
            } else {
                groups[groups.length - 1].push(run.text);
            }
        });
        const last = groups[groups.length - 1].join("").trim();
        const candidate = {
            videoId: videoId,
            title: titleRuns.length > 0 ? titleRuns[0].text : "",
            artists: groups[0].join("").split(/\s*(?:,|&)\s*/).filter(name => name),
            durationS: /^\d+(:\d{2}){1,2}$/.test(last) ? _durationSeconds(last) : 0,
        };
        const matched = videoId ? Match.score(candidate, q) : null;
        if (matched !== null) {
            ranked.push({ candidate: candidate, score: matched - rank, order: rank });
        }
    }
    ranked.sort((a, b) => b.score - a.score || a.order - b.order);
    return ranked.map(entry => entry.candidate);
}
