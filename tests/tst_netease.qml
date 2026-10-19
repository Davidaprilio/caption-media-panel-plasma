import QtQuick
import QtTest
import "../package/contents/code/lrclib.js" as Lrclib
import "../package/contents/code/netease.js" as Netease

TestCase {
    name: "NetEase"

    // Shaped like NetEase's answer for "Yuuri Dried Flower".
    readonly property var yuuri: ({ id: 100, name: "優里" })
    readonly property var searchResponse: ({
        code: 200,
        result: { songs: [
            { id: 1, name: "Dry Flower (Live)", transNames: null, alias: [], duration: 261000, artists: [{ id: 7, name: "ENHYPEN" }, yuuri] },
            { id: 2, name: "ドライフラワー", transNames: ["干花"], alias: [], duration: 286000, artists: [yuuri] },
            { id: 3, name: "ドライフラワー", transNames: ["Dried flower"], alias: [], duration: 286000, artists: [yuuri] },
            { id: 4, name: "Dried Flowers Chinese Version", transNames: null, alias: [], duration: 287000, artists: [yuuri] },
            { id: 5, name: "ドライフラワー（Cover優里）", transNames: null, alias: [], duration: 286000, artists: [{ id: 8, name: "深蓝瞳孔" }] },
        ] },
    })

    function test_searchUrl() {
        const q = Lrclib.query("Dried Flower (feat. Someone)", "Yuuri, Other", "", 286000);
        compare(Netease.searchUrl(q), "https://music.163.com/api/search/get?type=1&limit=10&s=Dried%20Flower%20Yuuri");
        compare(Netease.lyricUrl(42), "https://music.163.com/api/song/lyric?id=42&lv=-1&tv=-1&rv=-1");
    }

    function test_pickSong() {
        // Romanized artist, English title: the translated title matches.
        compare(Netease.pickSong(searchResponse, Lrclib.query("Dried Flower", "Yuuri", "", 286000)).id, 3);
        // Native artist and title: the first original release, not the cover.
        compare(Netease.pickSong(searchResponse, Lrclib.query("ドライフラワー", "優里", "", 286000)).id, 2);
        // Romanized artist, Japanese title: accepted on the (non-Latin) title.
        compare(Netease.pickSong(searchResponse, Lrclib.query("ドライフラワー", "Yuuri", "", 286000)).id, 2);
        // Artist matches but nothing else does: still the original, not the "Chinese Version".
        compare(Netease.pickSong(searchResponse, Lrclib.query("Something", "優里", "", 287000)).id, 2);
        // Neither artist nor title: nothing.
        compare(Netease.pickSong(searchResponse, Lrclib.query("Something", "Yuuri", "", 287000)), null);
        // A live recording is fine when the media itself is the live one.
        compare(Netease.pickSong(searchResponse, Lrclib.query("Dry Flower (Live)", "ENHYPEN, JAY, 優里", "", 261000)).id, 1);
        // Nothing within the duration.
        compare(Netease.pickSong(searchResponse, Lrclib.query("Dried Flower", "Yuuri", "", 200000)), null);
        compare(Netease.pickSong({ code: 200, result: {} }, Lrclib.query("x", "y", "", 0)), null);
        compare(Netease.pickSong(null, Lrclib.query("x", "y", "", 0)), null);
    }

    function test_pickSongRejectsOtherArtists() {
        // What NetEase answered once for "blue yung kai": same title, other
        // artists, close durations. Wrong lyrics are worse than none.
        const junk = { code: 200, result: { songs: [
            { id: 1, name: "blue", transNames: null, alias: [], duration: 215000, artists: [{ id: 1, name: "girl in red" }] },
            { id: 2, name: "告白气球", transNames: null, alias: [], duration: 214000, artists: [{ id: 2, name: "周杰伦" }] },
        ] } };
        compare(Netease.pickSong(junk, Lrclib.query("blue", "yung kai", "blue", 214000)), null);
        const real = { code: 200, result: { songs: junk.result.songs.concat([
            { id: 3, name: "blue (sped up)", transNames: null, alias: [], duration: 214000, artists: [{ id: 3, name: "yung kai" }] },
            { id: 4, name: "blue", transNames: null, alias: [], duration: 214000, artists: [{ id: 3, name: "yung kai" }] },
        ]) } };
        compare(Netease.pickSong(real, Lrclib.query("blue", "yung kai", "blue", 214000)).id, 4);
    }

    function test_rankSongs() {
        // An upload credited to "Yuuri" (artist id 0, like on NetEase) matches the
        // romanized artist best, but releases follow it as fallbacks.
        const upload = { id: 9, name: "ドライフラワー", transNames: null, alias: [], duration: 286000, artists: [{ id: 0, name: "Yuuri" }] };
        const response = { code: 200, result: { songs: [upload].concat(searchResponse.result.songs) } };
        const ranked = Netease.rankSongs(response, Lrclib.query("Dried Flower", "Yuuri", "", 286000));
        compare(ranked.map(song => song.id), [9, 3, 2], "upload (artist match), translated-title release, then its other release; no covers or other versions");
        const native = Netease.rankSongs(response, Lrclib.query("ドライフラワー", "優里", "", 286000));
        compare(native.map(song => song.id), [2, 3, 9], "official releases before the upload");
    }

    // Shaped like NetEase's lyrics: credits on top, romanization without the
    // credits and without the English line.
    readonly property var lyricResponse: ({
        code: 200,
        lrc: { lyric: "[00:00.00] 作词 : 優里\n[00:01.00] 作曲 : 優里\n[00:02.00] 编曲 : CHIMERAZ\n"
            + "[00:14.19]多分、私じゃなくていいね\n[00:17.47]余裕のない二人だったし\n[00:20.40]Say it back\n[00:23.34]ごめんね\n" },
        romalrc: { lyric: "[00:14.19]ta bu n、wa ta shi ja na ku te i i ne\n[00:17.470]yo yu u no na i fu ta ri da tta shi\n[00:23.34]go me n ne\n" },
        tlyric: { lyric: "[00:14.19]也许不是我也可以吧\n" },
    })

    function test_buildCuesRomanized() {
        const built = Netease.buildCues(lyricResponse, 286000, true);
        verify(built.romanized);
        compare(built.cues.map(cue => cue.text), [
            "ta bu n、wa ta shi ja na ku te i i ne",
            "yo yu u no na i fu ta ri da tta shi",
            "Say it back",          // no romanization for it: original kept
            "go me n ne",
        ]);
        compare(built.cues[0].start, 14190);
        compare(built.cues[0].end, 17470);
        compare(built.cues[1].start, 17470);
    }

    function test_buildCuesOriginal() {
        const built = Netease.buildCues(lyricResponse, 286000, false);
        verify(!built.romanized);
        compare(built.cues.map(cue => cue.text), ["多分、私じゃなくていいね", "余裕のない二人だったし", "Say it back", "ごめんね"]);
    }

    function test_buildCuesWithoutRomanization() {
        const response = { code: 200, lrc: lyricResponse.lrc, romalrc: { lyric: "" } };
        const built = Netease.buildCues(response, 286000, true);
        verify(!built.romanized, "falls back to the original lyrics");
        compare(built.cues.length, 4);
        compare(built.cues[0].text, "多分、私じゃなくていいね");
    }

    function test_buildCuesSpecialCases() {
        const instrumental = Netease.buildCues({ code: 200, lrc: { lyric: "[00:00.00]纯音乐，请欣赏\n" } }, 200000, true);
        compare(instrumental.cues.length, 1);
        compare(instrumental.cues[0].text, "♪ Instrumental ♪");
        compare(Netease.buildCues({ code: 200, nolyric: true }, 200000, true).cues.length, 0);
        compare(Netease.buildCues(null, 200000, true).cues.length, 0);
    }
}
