import QtQuick
import QtTest
import "../package/contents/ui/providers"
import "../package/contents/code/lrclib.js" as Lrclib

TestCase {
    id: test
    name: "Lrclib"

    function test_matchesPlayer() {
        const players = ["spotify"];
        const prefixes = ["https://open.spotify.com/"];
        verify(Lrclib.matchesPlayer("Spotify", "spotify", "", players, prefixes));
        verify(Lrclib.matchesPlayer("Spotify", "", "", players, prefixes));
        verify(Lrclib.matchesPlayer("Some Wrapper", "spotify", "", players, prefixes));
        verify(Lrclib.matchesPlayer("Brave", "", "https://open.spotify.com/track/1", players, prefixes));
        verify(!Lrclib.matchesPlayer("Brave", "", "https://www.youtube.com/watch?v=x", players, prefixes));
        verify(!Lrclib.matchesPlayer("Elisa", "org.kde.elisa", "", players, prefixes));
        verify(Lrclib.matchesPlayer("Elisa", "org.kde.elisa", "", ["spotify", "org.kde.elisa"], prefixes));
    }

    function test_cleanTitle_data() {
        return [
            { tag: "plain", title: "blue", clean: "blue" },
            { tag: "feat", title: "Song (feat. Someone)", clean: "Song" },
            { tag: "with brackets", title: "Song [with Other]", clean: "Song" },
            { tag: "remaster", title: "Heroes - 2017 Remaster", clean: "Heroes" },
            { tag: "live", title: "Song - Live at Wembley", clean: "Song" },
            { tag: "hyphen in name", title: "Re-Arranged", clean: "Re-Arranged" },
            { tag: "dash keeps title", title: "Part 1 - The Beginning", clean: "Part 1 - The Beginning" },
            { tag: "official video", title: "Ini Abadi (Official Music Video)", clean: "Ini Abadi" },
            { tag: "lyrics video", title: "Ini Abadi [Lirik]", clean: "Ini Abadi" },
            { tag: "audio", title: "Hati-Hati di Jalan (Official Audio)", clean: "Hati-Hati di Jalan" },
            { tag: "unrelated brackets stay", title: "Song (Part 2)", clean: "Song (Part 2)" },
        ];
    }

    function test_cleanTitle(data) {
        compare(Lrclib.cleanTitle(data.title), data.clean);
    }

    function test_urls() {
        const q = Lrclib.query("Song & Dance", "A, B", "Album", 214400);
        compare(q.durationS, 214);
        compare(q.firstArtist, "A");
        compare(Lrclib.getUrl(q), "https://lrclib.net/api/get?track_name=Song%20%26%20Dance&artist_name=A%2C%20B&album_name=Album&duration=214");
        compare(Lrclib.searchUrl(q), "https://lrclib.net/api/search?track_name=Song%20%26%20Dance&artist_name=A");
        // Unknown album and duration are left out.
        compare(Lrclib.getUrl(Lrclib.query("S", "A", "", 0)), "https://lrclib.net/api/get?track_name=S&artist_name=A");
        compare(Lrclib.getUrl(Lrclib.query("S", "A", "", 5 * 3600 * 1000)), "https://lrclib.net/api/get?track_name=S&artist_name=A");
    }

    function test_pickResult() {
        const results = [
            { id: 1, duration: 160, syncedLyrics: "[00:01.00]x" },
            { id: 2, duration: 214, syncedLyrics: null, plainLyrics: "plain" },
            { id: 3, duration: 216, syncedLyrics: "[00:01.00]x" },
            { id: 4, duration: 213, syncedLyrics: "[00:01.00]x" },
            { id: 5, duration: 214, instrumental: true },
        ];
        compare(Lrclib.pickResult(results, 214).id, 5);
        compare(Lrclib.pickResult(results.slice(0, 4), 214).id, 4);
        compare(Lrclib.pickResult(results.slice(0, 3), 214).id, 3);
        compare(Lrclib.pickResult(results.slice(0, 2), 214), null, "nothing synced within tolerance");
        compare(Lrclib.pickResult(results, 0).id, 1, "unknown duration: first usable");
        compare(Lrclib.pickResult([], 200), null);
    }

    function test_parseLrc() {
        const lrc = [
            "[ar:Someone]",
            "[ti:Song]",
            "[00:19.14] Your morning eyes",
            "[00:22.5]Second <00:23.00>line  with <00:24.10>word tags",
            "[00:26.140]",
            "[00:30.00][01:00.00] Chorus",
            "[00:30.00] together",
            "[00:45:50] colon fraction",
            "not a lyric line",
            "",
        ].join("\n");
        const cues = Lrclib.parseLrc(lrc, 120000);
        compare(cues.map(c => c.text), ["Your morning eyes", "Second line with word tags", "Chorus together", "colon fraction", "Chorus"]);
        compare(cues[0].start, 19140);
        compare(cues[0].end, 22500);
        compare(cues[1].start, 22500);
        compare(cues[1].end, 26140, "an empty line ends the previous one");
        compare(cues[2].start, 30000);
        compare(cues[2].end, 45000, "capped at 15 s");
        compare(cues[3].start, 45500);
        compare(cues[4].start, 60000);
        compare(cues[4].end, 75000, "last line: capped, not until the song ends");
        for (let i = 1; i < cues.length; ++i) {
            verify(cues[i].start >= cues[i - 1].end, "cues must not overlap");
        }
    }

    function test_parseLrcOffset() {
        const cues = Lrclib.parseLrc("[offset:+500]\n[00:10.00]a\n[00:12.00]b", 0);
        compare(cues[0].start, 9500);
        compare(cues[0].end, 11500);
        compare(cues[1].end, 11500 + 15000);
        compare(Lrclib.parseLrc("[offset:-250]\n[00:01.00]a", 3000)[0].start, 1250);
    }

    function test_recordToCues() {
        compare(Lrclib.recordToCues({ syncedLyrics: "[00:01.00]hi" }, 5000)[0].text, "hi");
        const instrumental = Lrclib.recordToCues({ instrumental: true, duration: 200 }, 0);
        compare(instrumental.length, 1);
        compare(instrumental[0].end, 200000);
        compare(Lrclib.recordToCues({ plainLyrics: "only plain" }, 1000).length, 0);
        compare(Lrclib.recordToCues(null, 1000).length, 0);
    }

    QtObject {
        id: spotifyMedia
        property string trackKey: "k"
        property string track: "blue"
        property string artist: "yung kai"
        property string album: "blue"
        property string identity: "Spotify"
        property string desktopEntry: "spotify"
        property real lengthMs: 214000
        property string url: ""
        property bool urlPending: false
    }

    Component {
        id: lrclibComponent
        // Never made active here, so no network requests happen.
        LrclibProvider {}
    }

    function test_providerCanHandle() {
        const p = createTemporaryObject(lrclibComponent, test, { media: spotifyMedia });
        verify(p.canHandle);
        compare(p.status, TranscriptProvider.Idle);
        spotifyMedia.identity = "VLC media player";
        spotifyMedia.desktopEntry = "vlc";
        verify(!p.canHandle);
        spotifyMedia.url = "https://open.spotify.com/track/abc";
        verify(p.canHandle, "Spotify web player");
        spotifyMedia.url = "https://music.youtube.com/watch?v=IpFX2vq8HKw";
        verify(p.canHandle, "YouTube Music");
        spotifyMedia.url = "https://www.youtube.com/watch?v=IpFX2vq8HKw";
        verify(!p.canHandle, "plain YouTube is left to YouTube captions");
        spotifyMedia.url = "";
        spotifyMedia.identity = "Spotify";
        spotifyMedia.artist = "";
        verify(!p.canHandle, "no artist (e.g. an ad)");
        spotifyMedia.artist = "yung kai";
    }
}
