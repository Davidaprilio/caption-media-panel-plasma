.pragma library

// A cue is { start: ms, end: ms, text: string }.
// Cue arrays are sorted by start and do not overlap.

// Index of the last cue that started at or before posMs, -1 if none did.
function indexAt(cues, posMs) {
    let lo = 0;
    let hi = cues.length - 1;
    let found = -1;
    while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (cues[mid].start <= posMs) {
            found = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return found;
}

// Next point in time (ms) where the displayed state changes, -1 if none.
function nextBoundary(cues, index, posMs) {
    if (index >= 0 && posMs < cues[index].end) {
        return cues[index].end;
    }
    if (index + 1 < cues.length) {
        return cues[index + 1].start;
    }
    return -1;
}

// Unique texts, so that width measurement does not repeat itself.
function uniqueTexts(cues) {
    const seen = new Set();
    for (let i = 0; i < cues.length; ++i) {
        seen.add(cues[i].text);
    }
    return Array.from(seen);
}

function formatTime(ms) {
    const total = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const mm = h > 0 && m < 10 ? "0" + m : String(m);
    const ss = s < 10 ? "0" + s : String(s);
    return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
}
