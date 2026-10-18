import QtQuick
import QtTest
import "../package/contents/code/youtube.js" as YouTube

TestCase {
    name: "YouTube"

    function test_videoIdFromUrl_data() {
        return [
            { tag: "watch", url: "https://www.youtube.com/watch?v=WtzhAytZ1OM", id: "WtzhAytZ1OM" },
            { tag: "watch params", url: "https://www.youtube.com/watch?list=PL1&v=WtzhAytZ1OM&t=42s", id: "WtzhAytZ1OM" },
            { tag: "mobile", url: "https://m.youtube.com/watch?v=WtzhAytZ1OM", id: "WtzhAytZ1OM" },
            { tag: "music", url: "https://music.youtube.com/watch?v=WtzhAytZ1OM&si=x", id: "WtzhAytZ1OM" },
            { tag: "short link", url: "https://youtu.be/WtzhAytZ1OM?t=3", id: "WtzhAytZ1OM" },
            { tag: "shorts", url: "https://www.youtube.com/shorts/WtzhAytZ1OM", id: "WtzhAytZ1OM" },
            { tag: "embed", url: "https://www.youtube.com/embed/WtzhAytZ1OM", id: "WtzhAytZ1OM" },
            { tag: "channel", url: "https://www.youtube.com/@someone", id: "" },
            { tag: "other site", url: "https://vimeo.com/123456", id: "" },
            { tag: "lookalike", url: "https://notyoutube.com/watch?v=WtzhAytZ1OM", id: "" },
            { tag: "file", url: "file:///home/me/video.mkv", id: "" },
            { tag: "empty", url: "", id: "" },
        ];
    }

    function test_videoIdFromUrl(data) {
        compare(YouTube.videoIdFromUrl(data.url), data.id);
    }

    function response(tracks) {
        return {
            playabilityStatus: { status: "OK" },
            captions: { playerCaptionsTracklistRenderer: { captionTracks: tracks } },
        };
    }

    function test_pickTrack() {
        const asrEn = { languageCode: "en", kind: "asr", baseUrl: "a" };
        const manualEn = { languageCode: "en", baseUrl: "b" };
        const manualId = { languageCode: "id", baseUrl: "c" };
        const manualDe = { languageCode: "de-DE", baseUrl: "d" };

        compare(YouTube.pickTrack(response([asrEn, manualEn, manualId]), ["id", "en"]), manualId);
        compare(YouTube.pickTrack(response([asrEn, manualEn]), ["id", "en"]), manualEn);
        // Manual captions in any language beat auto-generated ones.
        compare(YouTube.pickTrack(response([asrEn, manualDe]), ["id", "en"]), manualDe);
        compare(YouTube.pickTrack(response([asrEn]), ["id", "en"]), asrEn);
        compare(YouTube.pickTrack(response([]), ["en"]), null);
        compare(YouTube.pickTrack({ playabilityStatus: { status: "OK" } }, ["en"]), null);
        compare(YouTube.pickTrack(null, ["en"]), null);
    }

    function test_isPlayable() {
        verify(YouTube.isPlayable(response([])));
        verify(!YouTube.isPlayable({ playabilityStatus: { status: "LOGIN_REQUIRED" } }));
        verify(!YouTube.isPlayable(null));
    }

    function test_trackUrl() {
        compare(YouTube.trackUrl({ baseUrl: "https://x/api/timedtext?v=1&fmt=srv3&lang=en" }),
                "https://x/api/timedtext?v=1&lang=en&fmt=json3");
        compare(YouTube.trackUrl({ baseUrl: "https://x/api/timedtext?v=1" }), "https://x/api/timedtext?v=1&fmt=json3");
    }

    function test_trackLabel() {
        compare(YouTube.trackLabel({ languageCode: "en", name: { simpleText: "English (auto-generated)" } }), "English (auto-generated)");
        compare(YouTube.trackLabel({ languageCode: "en", name: { runs: [{ text: "Eng" }, { text: "lish" }] } }), "English");
        compare(YouTube.trackLabel({ languageCode: "en", kind: "asr" }), "en (auto)");
    }

    function test_json3ToCues() {
        // Shaped like auto-generated captions: rolling, overlapping lines,
        // newline-only "append" events and a speaker-change marker.
        const json3 = { events: [
            { tStartMs: 0, dDurationMs: 2674, segs: [{ utf8: "All" }] },
            { tStartMs: 644, dDurationMs: 2030, aAppend: 1, segs: [{ utf8: "\n" }] },
            { tStartMs: 654, dDurationMs: 2020, segs: [{ utf8: ">> " }, { utf8: "[music]" }] },
            { tStartMs: 6540, aAppend: 1, segs: [{ utf8: "\n" }] },
            { tStartMs: 10719, dDurationMs: 5481, segs: [{ utf8: "right," }, { utf8: " it's", tOffsetMs: 200 }, { utf8: " enough" }] },
            { tStartMs: 12800, dDurationMs: 3400, segs: [{ utf8: "Later,\nSpider-Man." }] },
            { tStartMs: 12800, dDurationMs: 1000, segs: [{ utf8: "Same start" }] },
            { tStartMs: 20000, segs: [{ utf8: "no duration" }] },
            { tStartMs: 30000, dDurationMs: 0 },
        ] };
        const cues = YouTube.json3ToCues(json3);
        compare(cues.map(c => c.text), ["All", "[music]", "right, it's enough", "Later, Spider-Man. Same start", "no duration"]);
        compare(cues[0].start, 0);
        compare(cues[0].end, 654);          // cut where the next line starts
        compare(cues[1].end, 2674);         // own duration, shorter than the gap
        compare(cues[2].end, 12800);
        compare(cues[3].end, 16200);
        compare(cues[4].end, 25000);        // no duration: 5 s
        for (let i = 1; i < cues.length; ++i) {
            verify(cues[i].start >= cues[i - 1].end, "cues must not overlap");
        }
        compare(YouTube.json3ToCues({}).length, 0);
        compare(YouTube.json3ToCues(null).length, 0);
    }

    function test_playerRequest() {
        const body = YouTube.playerRequest("WtzhAytZ1OM", YouTube.CLIENTS[0]);
        compare(body.videoId, "WtzhAytZ1OM");
        compare(body.context.client.clientName, YouTube.CLIENTS[0].clientName);
    }
}
