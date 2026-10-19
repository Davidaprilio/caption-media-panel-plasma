.pragma library
.import "lrclib.js" as Lrclib

// Synced lyrics from NetEase Cloud Music (unofficial API, no key). Besides the
// original lyrics it often has a synced romanization (romaji, Korean
// romanization), which is used when present.

const SEARCH_URL = "https://music.163.com/api/search/get";
const LYRIC_URL = "https://music.163.com/api/song/lyric";
// How far a result's duration may be off before it counts as another recording.
const DURATION_TOLERANCE_S = 3;
// Versions that are not the recording being played, unless its title says so.
const VERSION_WORDS = /\b(live|remix|cover|instrumental|karaoke|acoustic|version|ver\.|sped up|slowed|nightcore)\b|翻自|翻唱|伴奏|现场/i;
// Credit lines at the top of NetEase lyrics: "作词 : 優里", "编曲 : CHIMERAZ".
const CREDIT_LINE = /^[^:：]{1,20}\s[:：]\s/;
// NetEase's text for tracks without vocals.
const INSTRUMENTAL = /^纯音乐，?请欣赏/;

function searchUrl(q) {
    const terms = (Lrclib.cleanTitle(q.track) + " " + q.firstArtist).trim();
    return SEARCH_URL + "?type=1&limit=10&s=" + encodeURIComponent(terms);
}

function lyricUrl(songId) {
    // lv/tv/rv: original, translation and romanized lyrics.
    return LYRIC_URL + "?id=" + songId + "&lv=-1&tv=-1&rv=-1";
}

// Letters of non-Latin scripts: Greek to Thai and others, CJK, kana, Hangul,
// half-width katakana. (V4 has no \p{...} classes; they silently match nothing.)
const NON_LATIN = /[\u0370-\u1dbf\u1f00-\u1fff\u2e80-\u9fff\uac00-\ud7af\uf900-\ufaff\uff66-\uff9f]/;

function _normalize(text) {
    return String(text).toLowerCase().replace(/\s+/g, " ").trim();
}

// Without spaces and punctuation (ASCII, CJK and full-width), for comparing artist names.
function _compact(text) {
    return String(text).toLowerCase().replace(/[\s!-\/:-@\[-`{-~\u3000-\u303f\uff01-\uff0f\uff1a-\uff20]+/g, "");
}

function _artistMatches(song, artist) {
    const wanted = String(artist).split(/,|&| x | feat\.? /i).map(_compact).filter(name => name.length > 1);
    return (song.artists || []).some(a => {
        const name = _compact(a.name);
        return name.length > 1 && wanted.some(w => name === w || name.indexOf(w) !== -1 || w.indexOf(name) !== -1);
    });
}

// Search results that can be the track, best first. A candidate needs a
// matching duration (when known) and either a matching artist, or a matching
// title that is a translated title or in a non-Latin script: Asian artists
// often appear romanized in players ("Yuuri" for 優里), but a same-titled song
// by another artist is not accepted, and neither are other versions (live,
// cover, "Chinese Version", ...) unless the media is one. Uploads without a
// real artist rank lower; then NetEase's ranking decides. Other releases of
// an accepted song (same title and artist id) follow at the end: one of them
// may have the romanization the others lack.
function rankSongs(response, q) {
    const songs = (response && response.result && response.result.songs) || [];
    const title = _normalize(Lrclib.cleanTitle(q.track));
    const wantsVersion = VERSION_WORDS.test(q.track);
    const ranked = [];
    for (let rank = 0; rank < songs.length; ++rank) {
        const song = songs[rank];
        if (q.durationS > 0 && Math.abs(song.duration / 1000 - q.durationS) > DURATION_TOLERANCE_S) {
            continue;
        }
        const artistMatch = _artistMatches(song, q.artist);
        const nameMatch = _normalize(song.name) === title;
        const translatedMatch = (song.transNames || []).concat(song.alias || []).map(_normalize).indexOf(title) !== -1;
        if (!artistMatch && !translatedMatch && !(nameMatch && NON_LATIN.test(title))) {
            continue;
        }
        if (!wantsVersion && VERSION_WORDS.test(song.name)) {
            continue;
        }
        let score = -rank;
        if (artistMatch) {
            score += 100;
        }
        if (nameMatch || translatedMatch) {
            score += 50;
        }
        // Artist id 0: a user upload rather than a release.
        if ((song.artists || []).every(a => !a.id)) {
            score -= 30;
        }
        ranked.push({ song: song, score: score, order: rank });
    }
    // V4's sort is not stable; keep NetEase's order for equal scores.
    ranked.sort((a, b) => b.score - a.score || a.order - b.order);
    const accepted = ranked.map(entry => entry.song);

    const releases = [];
    for (const song of accepted) {
        for (const other of songs) {
            const sameArtist = (other.artists || []).some(a => a.id && (song.artists || []).some(b => b.id === a.id));
            if (sameArtist && _normalize(other.name) === _normalize(song.name)
                    && accepted.indexOf(other) === -1 && releases.indexOf(other) === -1
                    && (q.durationS <= 0 || Math.abs(other.duration / 1000 - q.durationS) <= DURATION_TOLERANCE_S)) {
                releases.push(other);
            }
        }
    }
    return accepted.concat(releases);
}

function pickSong(response, q) {
    return rankSongs(response, q)[0] || null;
}

function _cues(lrcText, durationMs) {
    return Lrclib.parseLrc(lrcText || "", durationMs).filter(cue => !CREDIT_LINE.test(cue.text));
}

// Lyric response -> { cues, romanized }. With preferRomanized, each line uses
// the romanized text when NetEase has one for it and the original otherwise
// (e.g. English lines in a Japanese song have no romanization).
function buildCues(response, durationMs, preferRomanized) {
    const original = _cues(response && response.lrc && response.lrc.lyric, durationMs);
    if (original.length === 1 && INSTRUMENTAL.test(original[0].text)) {
        return { cues: Lrclib.recordToCues({ instrumental: true }, durationMs), romanized: false };
    }
    if (!preferRomanized || original.length === 0) {
        return { cues: original, romanized: false };
    }
    const romanizedLines = _cues(response.romalrc && response.romalrc.lyric, durationMs);
    let replaced = 0;
    const cues = original.map(cue => {
        // Timestamps normally match exactly; allow a little rounding.
        const match = romanizedLines.find(line => Math.abs(line.start - cue.start) <= 50);
        if (!match) {
            return cue;
        }
        ++replaced;
        return { start: cue.start, end: cue.end, text: match.text };
    });
    return { cues: cues, romanized: replaced > 0 };
}
