import QtQuick
import QtTest
import "../package/contents/ui"
import "../package/contents/ui/providers"

TestCase {
    id: test
    name: "Providers"

    // Stands in for MediaSource.
    QtObject {
        id: fakeMedia
        property string trackKey: "t1"
        property string track: "Song"
        property string artist: ""
        property string identity: "Player"
        property real lengthMs: 0
        property string url: ""
        property bool urlPending: false
    }

    // Specialised provider that wants media with an artist.
    component LyricsProvider: TranscriptProvider {
        providerId: "lyrics"
        displayName: "Lyrics"
        canHandle: media !== null && media.artist !== ""
        property int loads: 0
        onActiveChanged: {
            if (active) {
                ++loads;
                setReady([{ start: 0, end: 1000, text: "la" }], "Lyrics · test");
            } else {
                reset();
            }
        }
    }

    // Specialised provider that wants a particular URL.
    component SiteProvider: TranscriptProvider {
        providerId: "site"
        displayName: "Site"
        canHandle: media !== null && media.url.startsWith("https://site.test/")
    }

    component Fallback: TranscriptProvider {
        providerId: "fallback"
        displayName: "Fallback"
        fallback: true
        canHandle: true
        Component.onCompleted: setReady([{ start: 0, end: 500, text: "dummy" }])
    }

    Component {
        id: sourceComponent
        TranscriptSource {
            media: fakeMedia
            providers: [
                SiteProvider {},
                LyricsProvider {},
                Fallback {}
            ]
        }
    }

    function init() {
        fakeMedia.artist = "";
        fakeMedia.url = "";
        fakeMedia.urlPending = false;
    }

    function provider(source, id) {
        for (let i = 0; i < source.providers.length; ++i) {
            if (source.providers[i].providerId === id) {
                return source.providers[i];
            }
        }
        return null;
    }

    function test_fallbackWhenNothingElseMatches() {
        const source = createTemporaryObject(sourceComponent, test);
        compare(source.current.providerId, "fallback");
        compare(source.status, TranscriptProvider.Ready);
        compare(source.cues[0].text, "dummy");
        compare(source.sourceName, "Fallback");
        verify(provider(source, "fallback").active);
        verify(!provider(source, "lyrics").active);
    }

    function test_specialisedProviderWins() {
        const source = createTemporaryObject(sourceComponent, test);
        fakeMedia.artist = "Band";
        compare(source.current.providerId, "lyrics");
        verify(provider(source, "lyrics").active);
        verify(!provider(source, "fallback").active);
        compare(source.cues[0].text, "la");
        compare(source.sourceName, "Lyrics · test");
        compare(provider(source, "lyrics").loads, 1);

        // Back to the fallback; the inactive provider resets itself.
        fakeMedia.artist = "";
        compare(source.current.providerId, "fallback");
        compare(provider(source, "lyrics").status, TranscriptProvider.Idle);
    }

    function test_listOrderIsPriority() {
        const source = createTemporaryObject(sourceComponent, test);
        fakeMedia.artist = "Band";
        fakeMedia.url = "https://site.test/watch/1";
        compare(source.current.providerId, "site");
    }

    function test_disabledProviderIsSkipped() {
        const source = createTemporaryObject(sourceComponent, test);
        fakeMedia.artist = "Band";
        provider(source, "lyrics").enabled = false;
        compare(source.current.providerId, "fallback");
        provider(source, "fallback").enabled = false;
        compare(source.current, null);
        compare(source.status, TranscriptProvider.Idle);
        compare(source.cues.length, 0);
    }

    function test_pendingUrlHoldsBackTheFallback() {
        const source = createTemporaryObject(sourceComponent, test);
        fakeMedia.urlPending = true;
        compare(source.current, null);
        compare(source.status, TranscriptProvider.Loading);
        // A specialised match is used even while the URL is pending.
        fakeMedia.artist = "Band";
        compare(source.current.providerId, "lyrics");
        fakeMedia.artist = "";
        fakeMedia.urlPending = false;
        compare(source.current.providerId, "fallback");
    }

    function test_languagesAreWired() {
        const source = createTemporaryObject(sourceComponent, test, { languages: ["id", "en"] });
        compare(provider(source, "site").languages, ["id", "en"]);
        source.languages = ["en"];
        compare(provider(source, "lyrics").languages, ["en"]);
    }

    Component {
        id: bareProvider
        TranscriptProvider {
            providerId: "bare"
            displayName: "Bare"
        }
    }

    function test_providerHelpers() {
        const p = createTemporaryObject(bareProvider, test, { cacheSize: 2 });
        compare(p.status, TranscriptProvider.Idle);
        p.setLoading();
        compare(p.status, TranscriptProvider.Loading);
        p.setReady([]);
        compare(p.status, TranscriptProvider.Unavailable, "no cues is not ready");
        p.setReady([{ start: 0, end: 1, text: "x" }], "Bare · en");
        compare(p.status, TranscriptProvider.Ready);
        compare(p.sourceName, "Bare · en");
        p.reset();
        compare(p.cues.length, 0);
        compare(p.sourceName, "Bare");

        p.remember("a", 1);
        p.remember("b", 2);
        p.remember("a", 3);
        compare(p.cached("a"), 3);
        p.remember("c", 4);
        compare(p.cached("a"), undefined, "oldest entry evicted");
        compare(p.cached("b"), 2);
        compare(p.cached("c"), 4);
    }
}
