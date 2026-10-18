.pragma library

// Synced lyrics from LRCLIB (https://lrclib.net), a free lyrics database.

const API = "https://lrclib.net/api";
const USER_AGENT = "caption-media-panel/0.1.0 (KDE Plasma widget)";

// /api/get accepts durations in this range (seconds).
const MIN_DURATION_S = 1;
const MAX_DURATION_S = 3600;
// How far a search result's duration may be off before it counts as another recording.
const SEARCH_TOLERANCE_S = 3;
// A line is not kept on screen longer than this when nothing follows it.
const MAX_LINE_MS = 15000;

// True if the media comes from one of `players` (matched case-insensitively
// against the MPRIS identity and desktop entry) or from a page URL starting
// with one of `urlPrefixes`.
function matchesPlayer(identity, desktopEntry, url, players, urlPrefixes) {
    const names = [String(identity).toLowerCase(), String(desktopEntry).toLowerCase()];
    for (let i = 0; i < players.length; ++i) {
        if (names.indexOf(players[i]) !== -1) {
            return true;
        }
    }
    for (let i = 0; i < urlPrefixes.length; ++i) {
        if (url && url.startsWith(urlPrefixes[i])) {
            return true;
        }
    }
    return false;
}

// Drops decorations that lyric databases usually don't have in the title:
// "(feat. X)", "[with Y]", " - Remastered 2011", " - Live", ...
function cleanTitle(title) {
    return String(title)
        .replace(/\s*[\(\[](?:feat\.?|ft\.?|with)\s[^\)\]]*[\)\]]/gi, "")
        .replace(/\s+-\s+[^-]*(?:remaster|version|edit|mono|stereo|live|mix|demo)[^-]*$/i, "")
        .trim();
}

function query(track, artist, album, lengthMs) {
    return {
        track: track,
        artist: artist,
        // kmpris joins several artists with ", ".
        firstArtist: String(artist).split(", ")[0],
        album: album || "",
        durationS: lengthMs > 0 ? Math.round(lengthMs / 1000) : 0,
    };
}

function _params(pairs) {
    return pairs.filter(pair => pair[1] !== "" && pair[1] !== null)
        .map(pair => pair[0] + "=" + encodeURIComponent(pair[1]))
        .join("&");
}

function getUrl(q) {
    const duration = q.durationS >= MIN_DURATION_S && q.durationS <= MAX_DURATION_S ? q.durationS : "";
    return API + "/get?" + _params([["track_name", q.track], ["artist_name", q.artist], ["album_name", q.album], ["duration", duration]]);
}

function searchUrl(q) {
    return API + "/search?" + _params([["track_name", cleanTitle(q.track)], ["artist_name", q.firstArtist]]);
}

function isUsable(record) {
    return !!record && (!!record.syncedLyrics || record.instrumental === true);
}

// Best search result: usable, and when the duration is known, the closest
// one within SEARCH_TOLERANCE_S.
function pickResult(results, durationS) {
    let best = null;
    let bestDiff = Infinity;
    for (let i = 0; i < results.length; ++i) {
        const record = results[i];
        if (!isUsable(record)) {
            continue;
        }
        if (!(durationS > 0)) {
            return record;
        }
        const diff = Math.abs(record.duration - durationS);
        if (diff <= SEARCH_TOLERANCE_S && diff < bestDiff) {
            best = record;
            bestDiff = diff;
        }
    }
    return best;
}

// "[mm:ss.xx]" fraction digits -> ms ("5" = 500, "14" = 140, "140" = 140).
function _timeMs(minutes, seconds, fraction) {
    const fractionMs = fraction ? Math.round(parseInt(fraction, 10) * Math.pow(10, 3 - fraction.length)) : 0;
    return parseInt(minutes, 10) * 60000 + parseInt(seconds, 10) * 1000 + fractionMs;
}

// LRC text -> cues. Handles several timestamps per line, [offset:], word
// timing tags ("<00:12.34>"), and empty lines (they end the previous line).
function parseLrc(text, durationMs) {
    const stamp = /^\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]/;
    const entries = [];
    let offset = 0;
    const lines = String(text).split(/\r?\n/);
    for (let i = 0; i < lines.length; ++i) {
        let rest = lines[i].trim();
        const times = [];
        let match;
        while ((match = stamp.exec(rest))) {
            times.push(_timeMs(match[1], match[2], match[3]));
            // No String.prototype.trimStart in V4.
            rest = rest.slice(match[0].length).replace(/^\s+/, "");
        }
        if (times.length === 0) {
            const tag = /^\[offset:\s*([+-]?\d+)\s*\]$/i.exec(rest);
            if (tag) {
                offset = parseInt(tag[1], 10);
            }
            continue;
        }
        const lyric = rest.replace(/<\d+:\d{1,2}(?:[.:]\d{1,3})?>/g, "").replace(/\s+/g, " ").trim();
        for (let t = 0; t < times.length; ++t) {
            entries.push({ time: times[t], text: lyric, order: entries.length });
        }
    }
    // V4's sort is not stable; keep document order for equal times.
    entries.sort((a, b) => a.time - b.time || a.order - b.order);

    const cues = [];
    for (let i = 0; i < entries.length; ++i) {
        if (!entries[i].text) {
            continue;
        }
        // A positive offset shows the lyrics earlier.
        const start = Math.max(0, entries[i].time - offset);
        // Lines sharing a timestamp are merged below; the line ends at the next different one.
        let n = i + 1;
        while (n < entries.length && entries[n].time === entries[i].time) {
            ++n;
        }
        const next = entries[n];
        let end = next ? Math.max(0, next.time - offset) : (durationMs > start ? durationMs : start + MAX_LINE_MS);
        end = Math.min(end, start + MAX_LINE_MS);
        const previous = cues[cues.length - 1];
        if (previous && previous.start === start) {
            previous.text += " " + entries[i].text;
            continue;
        }
        if (end > start) {
            cues.push({ start: start, end: end, text: entries[i].text });
        }
    }
    return cues;
}

function recordToCues(record, durationMs) {
    if (!record) {
        return [];
    }
    if (record.syncedLyrics) {
        return parseLrc(record.syncedLyrics, durationMs);
    }
    if (record.instrumental) {
        const length = durationMs > 0 ? durationMs : (record.duration || 0) * 1000;
        return [{ start: 0, end: length > 0 ? length : MAX_LINE_MS, text: "♪ Instrumental ♪" }];
    }
    return [];
}
