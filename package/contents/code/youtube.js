.pragma library

// YouTube captions through the (unofficial) InnerTube player API.
//
// The caption URLs embedded in the web watch page need a proof-of-origin token
// (they carry "exp=xpe" and return an empty body without it). The mobile
// clients below currently get caption URLs that work without one. Clients are
// tried in order; when YouTube breaks one, bump its version or reorder here.
const CLIENTS = [
    { clientName: "ANDROID", clientVersion: "20.10.38" },
    { clientName: "IOS", clientVersion: "20.10.4" },
];

const PLAYER_URL = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false";

const ID_PATTERN = /^https?:\/\/(?:www\.|m\.|music\.)?(?:youtube\.com\/(?:watch\?(?:[^#]*&)?v=|shorts\/|embed\/|live\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/;

// Video id from a YouTube page URL, "" for anything else.
function videoIdFromUrl(url) {
    const match = url ? ID_PATTERN.exec(url) : null;
    return match ? match[1] : "";
}

// 320x180 thumbnail of a YouTube page URL, "" for anything else.
function thumbnailUrl(url) {
    const id = videoIdFromUrl(url);
    return id ? "https://i.ytimg.com/vi/" + id + "/mqdefault.jpg" : "";
}

function playerRequest(videoId, client) {
    return {
        context: { client: { clientName: client.clientName, clientVersion: client.clientVersion, hl: "en" } },
        videoId: videoId,
    };
}

function captionTracks(playerResponse) {
    const captions = playerResponse && playerResponse.captions;
    const list = captions && captions.playerCaptionsTracklistRenderer;
    return (list && list.captionTracks) || [];
}

function isPlayable(playerResponse) {
    const status = playerResponse && playerResponse.playabilityStatus;
    return !!status && status.status === "OK";
}

// Best track: manual captions before auto-generated ones, then by position of
// the track's language in `languages` (e.g. ["id", "en"]).
function pickTrack(playerResponse, languages) {
    const tracks = captionTracks(playerResponse);
    let best = null;
    let bestRank = Infinity;
    for (let i = 0; i < tracks.length; ++i) {
        const track = tracks[i];
        let language = languages.indexOf(String(track.languageCode).split("-")[0]);
        if (language < 0) {
            language = languages.length;
        }
        const rank = (track.kind === "asr" ? 100 : 0) + language;
        if (rank < bestRank) {
            best = track;
            bestRank = rank;
        }
    }
    return best;
}

function trackUrl(track) {
    return track.baseUrl.replace(/&fmt=[^&]*/g, "") + "&fmt=json3";
}

function trackLabel(track) {
    const name = track.name || {};
    if (name.simpleText) {
        return name.simpleText;
    }
    if (name.runs) {
        return name.runs.map(run => run.text).join("");
    }
    return track.languageCode + (track.kind === "asr" ? " (auto)" : "");
}

// json3 caption events -> cues ({ start, end, text } in ms, sorted, no overlap).
// Auto-generated captions roll two lines at a time, so events overlap; each
// cue is cut off where the next one starts.
function json3ToCues(json3) {
    const events = (json3 && json3.events) || [];
    const cues = [];
    for (let i = 0; i < events.length; ++i) {
        const event = events[i];
        if (!event.segs) {
            continue;
        }
        const text = event.segs.map(seg => seg.utf8 || "").join("")
            .replace(/\s+/g, " ")
            .replace(/^>>\s*/, "")   // speaker-change marker
            .trim();
        if (!text) {
            continue;
        }
        const start = event.tStartMs || 0;
        cues.push({ start: start, end: start + (event.dDurationMs || 0), text: text, order: cues.length });
    }
    // V4's sort is not stable; keep document order for equal start times.
    cues.sort((a, b) => a.start - b.start || a.order - b.order);
    cues.forEach(cue => delete cue.order);

    const merged = [];
    for (let i = 0; i < cues.length; ++i) {
        const previous = merged[merged.length - 1];
        if (previous && previous.start === cues[i].start) {
            previous.text += " " + cues[i].text;
            previous.end = Math.max(previous.end, cues[i].end);
        } else {
            merged.push(cues[i]);
        }
    }
    for (let i = 0; i < merged.length; ++i) {
        const next = merged[i + 1];
        if (next && merged[i].end > next.start) {
            merged[i].end = next.start;
        }
        if (merged[i].end <= merged[i].start) {
            // No duration given: show it until the next line, at most 5 s.
            merged[i].end = next ? Math.min(next.start, merged[i].start + 5000) : merged[i].start + 5000;
        }
    }
    return merged;
}
