import QtQuick
import QtTest
import "../package/contents/code/lrclib.js" as Lrclib
import "../package/contents/code/ytmusic.js" as YTMusic

TestCase {
    name: "YouTubeMusic"

    function test_videoIdFromUrl() {
        compare(YTMusic.videoIdFromUrl("https://music.youtube.com/watch?v=0cAcD7IvLHI&list=RDAMVM0cAcD7IvLHI"), "0cAcD7IvLHI");
        compare(YTMusic.videoIdFromUrl("https://www.youtube.com/watch?v=0cAcD7IvLHI"), "", "plain YouTube is not YouTube Music");
        compare(YTMusic.videoIdFromUrl("https://open.spotify.com/track/1"), "");
        compare(YTMusic.videoIdFromUrl(""), "");
    }

    function test_requests() {
        const next = YTMusic.nextRequest("E7kHvjvU6JY");
        compare(next.videoId, "E7kHvjvU6JY");
        compare(next.context.client.clientName, "WEB_REMIX");
        verify(/^1\.\d{8}\.01\.00$/.test(next.context.client.clientVersion), next.context.client.clientVersion);
        // Timestamps need the mobile client.
        compare(YTMusic.browseRequest("MPLYt_x").context.client.clientName, "ANDROID_MUSIC");
        compare(YTMusic.browseRequest("MPLYt_x").browseId, "MPLYt_x");
        const search = YTMusic.searchRequest(Lrclib.query("Hati-Hati di Jalan (feat. X)", "Tulus, Y", "", 242000));
        compare(search.query, "Hati-Hati di Jalan Tulus");
        compare(search.params, YTMusic.SONGS_FILTER);
    }

    // Shaped like a real next response: tabs Up next, Lyrics, Related.
    function nextResponse(lyricsTab) {
        const tab = (browseId, pageType) => ({ tabRenderer: { endpoint: { browseEndpoint: {
            browseId: browseId,
            browseEndpointContextSupportedConfigs: { browseEndpointContextMusicConfig: { pageType: pageType } },
        } } } });
        const tabs = [{ tabRenderer: { title: "Up next" } }];
        if (lyricsTab) {
            tabs.push(tab("MPLYt_7FNmIeIV9kf-8", "MUSIC_PAGE_TYPE_TRACK_LYRICS"));
        }
        tabs.push(tab("MPTRt_related", "MUSIC_PAGE_TYPE_TRACK_RELATED"));
        return { contents: { singleColumnMusicWatchNextResultsRenderer: { tabbedRenderer: { watchNextTabbedResultsRenderer: { tabs: tabs } } } } };
    }

    function test_lyricsBrowseId() {
        compare(YTMusic.lyricsBrowseId(nextResponse(true)), "MPLYt_7FNmIeIV9kf-8");
        compare(YTMusic.lyricsBrowseId(nextResponse(false)), "", "no lyrics tab");
        compare(YTMusic.lyricsBrowseId({}), "");
        compare(YTMusic.lyricsBrowseId(null), "");
    }

    // Shaped like the mobile client's browse response.
    function browseResponse(lines, source) {
        return { contents: { elementRenderer: { newElement: { type: { componentType: { model: { timedLyricsModel: {
            lyricsData: { timedLyricsData: lines, sourceMessage: source },
        } } } } } } } };
    }

    function timed(text, start, end, id) {
        return { lyricLine: text, cueRange: { startTimeMilliseconds: String(start), endTimeMilliseconds: String(end), metadata: { id: String(id) } } };
    }

    function test_timedCues() {
        const result = YTMusic.timedCues(browseResponse([
            timed("Iyalah", 7920, 10450, 1),
            timed("Kamu  siapa namanya", 10450, 14630, 2),
            timed("", 14630, 15000, 3),                 // empty line: dropped
            timed("Rumahnya juga di mana", 14900, 18650, 4),
        ], "Source: LyricFind"));
        compare(result.source, "LyricFind");
        compare(result.cues.map(cue => cue.text), ["Iyalah", "Kamu siapa namanya", "Rumahnya juga di mana"]);
        compare(result.cues[0].start, 7920);
        compare(result.cues[0].end, 10450);
        compare(result.cues[1].end, 14630);
        compare(result.cues[2].start, 14900);
    }

    function test_timedCuesTrimsOverlaps() {
        const result = YTMusic.timedCues(browseResponse([timed("a", 0, 3000, 1), timed("b", 2500, 4000, 2)], "Source: Musixmatch"));
        compare(result.cues[0].end, 2500);
        compare(result.source, "Musixmatch");
    }

    function test_plainLyricsAreRejected() {
        // Music videos often come back like this: lines without cueRange.
        compare(YTMusic.timedCues(browseResponse([{ lyricLine: "Know you're all that I want" }, { lyricLine: "this life" }], "Source: Musixmatch")), null);
        compare(YTMusic.timedCues(browseResponse([timed("a", 0, 1000, 1), { lyricLine: "b" }], "")), null, "partly timed is not timed");
        compare(YTMusic.timedCues(browseResponse([], "")), null);
        compare(YTMusic.timedCues({ contents: { elementRenderer: {} } }), null);
        compare(YTMusic.timedCues(null), null);
    }

    function test_plainLyrics() {
        const plain = YTMusic.plainLyrics(browseResponse([
            { lyricLine: " Know you're all that I want " },
            { lyricLine: "" }, { lyricLine: "" }, { lyricLine: "" },
            { lyricLine: "this life" },
        ], "Source: LyricFind"));
        compare(plain.text, "Know you're all that I want\n\nthis life", "trimmed, at most one blank line");
        compare(plain.source, "LyricFind");
        compare(YTMusic.plainLyrics(browseResponse([timed("a", 0, 1000, 1), { lyricLine: "b" }], "")).text, "a\nb", "partly timed is plain");
        compare(YTMusic.plainLyrics(browseResponse([timed("a", 0, 1000, 1)], "")), null, "synced lyrics are not plain");
        compare(YTMusic.plainLyrics(browseResponse([{ lyricLine: " " }], "")), null);
        compare(YTMusic.plainLyrics(browseResponse([], "")), null);
        compare(YTMusic.plainLyrics(null), null);
    }

    // Shaped like a "Songs" search result row.
    function song(videoId, title, artists, album, duration) {
        const second = [];
        artists.forEach((artist, i) => {
            if (i > 0) {
                second.push({ text: " & " });
            }
            second.push({ text: artist, navigationEndpoint: { browseEndpoint: {} } });
        });
        second.push({ text: " • " }, { text: album }, { text: " • " }, { text: duration });
        return { musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: videoId },
            flexColumns: [
                { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: title }] } } },
                { musicResponsiveListItemFlexColumnRenderer: { text: { runs: second } } },
                { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "329M plays" }] } } },
            ],
        } };
    }

    function searchResponse(rows) {
        return { contents: { tabbedSearchResultsRenderer: { tabs: [{ tabRenderer: { content: { sectionListRenderer: { contents: [
            { musicShelfRenderer: { contents: rows } },
        ] } } } }] } } };
    }

    function test_searchCandidates() {
        const response = searchResponse([
            song("5F28ye50-Kc", "Teh Hijau", ["Tulus"], "Teh Hijau", "3:33"),
            song("E7kHvjvU6JY", "Hati-Hati di Jalan", ["Tulus"], "Manusia", "4:02"),
            song("live1", "Hati-Hati di Jalan (Live)", ["Tulus"], "Live", "4:03"),
            song("other", "Hati-Hati di Jalan", ["Someone Else"], "Cover Album", "4:02"),
        ]);
        const q = Lrclib.query("Hati-Hati di Jalan", "Tulus", "Manusia", 242000);
        const ids = YTMusic.searchCandidates(response, q).map(candidate => candidate.videoId);
        compare(ids[0], "E7kHvjvU6JY", "title and artist match first");
        verify(ids.indexOf("live1") === -1, "other versions are left out");
        verify(ids.indexOf("other") === -1, "a same-titled song by another artist is left out");
        verify(ids.indexOf("5F28ye50-Kc") === -1, "another song by the artist has another duration");
    }

    function test_artistInTitle() {
        // An upload by "Yunita" titled "Perunggu Ini Abadi", next to the real song.
        const response = searchResponse([
            song("sEN4kflBIQk", "Perunggu Ini Abadi", ["Yunita"], "Perunggu Ini Abadi", "4:40"),
            song("ASBUp9jG6LI", "Ini Abadi", ["Perunggu"], "Memorandum", "3:52"),
            song("_eVLDvD7lE8", "33x", ["Perunggu"], "Memorandum", "3:52"),
        ]);
        // Same length as the release: its lyrics fit.
        const sameLength = YTMusic.searchCandidates(response, Lrclib.query("Perunggu Ini Abadi", "Yunita", "", 232000));
        compare(sameLength.map(candidate => candidate.videoId), ["ASBUp9jG6LI"]);
        // The upload actually playing is 4:40: the release's timing would be off.
        const otherLength = YTMusic.searchCandidates(response, Lrclib.query("Perunggu Ini Abadi", "Yunita", "", 280000));
        compare(otherLength.map(candidate => candidate.videoId), ["sEN4kflBIQk"], "only the upload itself");
    }

    function test_searchCandidatesDetails() {
        const response = searchResponse([song("ditto", "Ditto", ["NewJeans", "Other"], "OMG", "3:06"), song("long", "Long", ["Xavier"], "Y", "1:02:03")]);
        const ditto = YTMusic.searchCandidates(response, Lrclib.query("Ditto", "NewJeans", "", 186000))[0];
        compare(ditto.artists, ["NewJeans", "Other"]);
        compare(ditto.durationS, 186);
        compare(YTMusic.searchCandidates(response, Lrclib.query("Long", "Xavier", "", 3723000))[0].durationS, 3723);
        compare(YTMusic.searchCandidates({}, Lrclib.query("Ditto", "NewJeans", "", 0)).length, 0);
    }
}
