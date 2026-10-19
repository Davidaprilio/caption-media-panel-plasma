.pragma library
.import "lrclib.js" as Lrclib

// Whether a catalogue search result is the recording being played. Shared by
// the lyrics providers that search (NetEase, YouTube Music).

// How far a result's duration may be off before it counts as another recording.
const DURATION_TOLERANCE_S = 3;
// Versions that are not the recording being played, unless its title says so.
const VERSION_WORDS = /\b(live|remix|cover|instrumental|karaoke|acoustic|version|ver\.|sped up|slowed|nightcore)\b|翻自|翻唱|伴奏|现场/i;
// Letters of non-Latin scripts: Greek to Thai and others, CJK, kana, Hangul,
// half-width katakana. (V4 has no \p{...} classes; they silently match nothing.)
const NON_LATIN = /[Ͱ-ᶿἀ-῿⺀-鿿가-힯豈-﫿ｦ-ﾟ]/;

function normalize(text) {
    return String(text).toLowerCase().replace(/\s+/g, " ").trim();
}

// Without spaces and punctuation (ASCII, CJK and full-width), for comparing artist names.
function compact(text) {
    return String(text).toLowerCase().replace(/[\s!-\/:-@\[-`{-~　-〿！-／：-＠]+/g, "");
}

// True if one of `names` is (part of) one of the artists in `artist`
// ("A, B & C feat. D").
function artistMatches(names, artist) {
    const wanted = String(artist).split(/,|&| x | feat\.? /i).map(compact).filter(name => name.length > 1);
    return names.some(raw => {
        const name = compact(raw);
        return name.length > 1 && wanted.some(w => name === w || name.indexOf(w) !== -1 || w.indexOf(name) !== -1);
    });
}

// Score of a candidate for the query `q` (lrclib.js query()), or null when it
// cannot be the track. candidate: { title, otherTitles: [translated titles,
// aliases], artists: [names], durationS }.
//
// It needs a matching duration (when both are known) and either a matching
// artist, or a matching title that is a translated title or in a non-Latin
// script: Asian artists often appear romanized in players ("Yuuri" for 優里),
// but a same-titled song by another artist is not accepted, and neither are
// other versions (live, cover, "Chinese Version", ...) unless the media is one.
// Uploads that put the artist into the title ("Perunggu Ini Abadi" by the
// uploader) match a candidate whose title and artist both appear in it.
function score(candidate, q) {
    if (q.durationS > 0 && candidate.durationS > 0
            && Math.abs(candidate.durationS - q.durationS) > DURATION_TOLERANCE_S) {
        return null;
    }
    const title = normalize(Lrclib.cleanTitle(q.track));
    const candidateTitle = normalize(candidate.title);
    const inTitle = candidateTitle.length > 1 && title !== candidateTitle && title.indexOf(candidateTitle) !== -1
        && artistMatches(candidate.artists || [], title.replace(candidateTitle, " "));
    const artistMatch = inTitle || artistMatches(candidate.artists || [], q.artist);
    const nameMatch = inTitle || candidateTitle === title;
    const translatedMatch = (candidate.otherTitles || []).map(normalize).indexOf(title) !== -1;
    if (!artistMatch && !translatedMatch && !(nameMatch && NON_LATIN.test(title))) {
        return null;
    }
    if (!VERSION_WORDS.test(q.track) && VERSION_WORDS.test(candidate.title)) {
        return null;
    }
    return (artistMatch ? 100 : 0) + (nameMatch || translatedMatch ? 50 : 0);
}
