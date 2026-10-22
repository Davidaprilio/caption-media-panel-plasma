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
        property bool needsBrowserIntegration: false
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

    // Claims "multi" URLs but has nothing for them; answers later, like a network request.
    component EmptyProvider: TranscriptProvider {
        providerId: "empty"
        displayName: "Empty"
        canHandle: media !== null && media.url.startsWith("https://multi.test/")
        property int loads: 0
        // Works while in use or probed, like the real providers.
        readonly property bool working: active || probing
        onWorkingChanged: {
            if (working) {
                ++loads;
                Qt.callLater(setUnavailable, "test: nothing here");
            } else {
                reset();
            }
        }
    }

    // Same, but answers at once, like a cached miss.
    component CachedEmptyProvider: TranscriptProvider {
        providerId: "cachedEmpty"
        displayName: "Cached empty"
        canHandle: media !== null && media.url.startsWith("https://multi.test/")
        readonly property bool working: active || probing
        onWorkingChanged: working ? setReady([]) : reset()
    }

    component SecondProvider: TranscriptProvider {
        providerId: "second"
        displayName: "Second"
        canHandle: media !== null && media.url.startsWith("https://multi.test/")
        readonly property bool working: active || probing
        onWorkingChanged: working ? setReady([{ start: 0, end: 1000, text: "second" }]) : reset()
    }

    component ThirdProvider: TranscriptProvider {
        providerId: "third"
        displayName: "Third"
        canHandle: media !== null && media.url.startsWith("https://multi.test/")
        readonly property bool working: active || probing
        onWorkingChanged: working ? setReady([{ start: 0, end: 1000, text: "third" }], "Third · test") : reset()
    }

    // Gives up with unsynced lyrics (like YouTube Music for a music video).
    component PlainProvider: TranscriptProvider {
        property string lyrics: "la\nla"
        providerId: "plain"
        displayName: "Plain"
        canHandle: media !== null && media.url.startsWith("https://multi.test/")
        readonly property bool working: active || probing
        onWorkingChanged: working ? Qt.callLater(setPlainOnly, lyrics, displayName + " · test") : reset()
    }

    Component {
        id: plainComponent
        TranscriptSource {
            media: fakeMedia
            providers: [
                PlainProvider {},
                EmptyProvider {},
                PlainProvider {
                    providerId: "laterPlain"
                    displayName: "Later plain"
                    lyrics: "lower priority"
                },
                Fallback {}
            ]
        }
    }

    Component {
        id: spyComponent
        SignalSpy {}
    }

    Component {
        id: plainThenSyncedComponent
        TranscriptSource {
            media: fakeMedia
            providers: [
                PlainProvider {},
                SecondProvider {},
                Fallback {}
            ]
        }
    }

    Component {
        id: realDummyComponent
        TranscriptSource {
            media: fakeMedia
            providers: [DummyProvider {}]
        }
    }

    Component {
        id: probeComponent
        TranscriptSource {
            media: fakeMedia
            providers: [
                EmptyProvider {},
                SecondProvider {},
                ThirdProvider {},
                Fallback {}
            ]
        }
    }

    Component {
        id: cascadeComponent
        TranscriptSource {
            media: fakeMedia
            providers: [
                EmptyProvider {},
                CachedEmptyProvider {},
                SecondProvider {},
                Fallback {}
            ]
        }
    }

    Component {
        id: allEmptyComponent
        TranscriptSource {
            media: fakeMedia
            providers: [
                EmptyProvider {},
                CachedEmptyProvider {},
                Fallback {}
            ]
        }
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
        fakeMedia.trackKey = "t1";
        fakeMedia.artist = "";
        fakeMedia.url = "";
        fakeMedia.urlPending = false;
        fakeMedia.needsBrowserIntegration = false;
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

    function test_cascadeToNextProvider() {
        const source = createTemporaryObject(cascadeComponent, test);
        fakeMedia.url = "https://multi.test/a";
        compare(source.current.providerId, "empty");
        // Async miss, then a synchronous (cached) miss, then a provider with cues.
        tryCompare(source, "sourceName", "Second");
        compare(source.current.providerId, "second");
        compare(source.status, TranscriptProvider.Ready);
        compare(source.cues[0].text, "second");
        compare(provider(source, "empty").loads, 1);
        verify(!provider(source, "empty").active);
    }

    function test_cascadeStartsOverForNewMedia() {
        const source = createTemporaryObject(cascadeComponent, test);
        fakeMedia.url = "https://multi.test/a";
        tryCompare(source, "sourceName", "Second");
        fakeMedia.trackKey = "t2";
        compare(source.current.providerId, "empty", "first choice again for another track");
        tryCompare(source, "sourceName", "Second");
        compare(provider(source, "empty").loads, 2);
    }

    function test_cascadeNeverFallsBackToTheFallback() {
        const source = createTemporaryObject(allEmptyComponent, test);
        fakeMedia.url = "https://multi.test/a";
        tryCompare(source, "status", TranscriptProvider.Unavailable);
        wait(50);
        compare(source.current.providerId, "cachedEmpty", "stays on the last provider that gave up");
        compare(source.status, TranscriptProvider.Unavailable);
        compare(source.cues.length, 0);
        // Media nobody claims still gets the fallback.
        fakeMedia.url = "";
        compare(source.current.providerId, "fallback");
    }

    function test_plainLyricsWhenNothingIsSynced() {
        const source = createTemporaryObject(plainComponent, test);
        const changes = createTemporaryObject(spyComponent, test, { target: source, signalName: "plainTextChanged" });
        fakeMedia.url = "https://multi.test/a";
        compare(source.plainText, "", "not while providers are still looking");
        tryCompare(source, "status", TranscriptProvider.Unavailable);
        wait(50);
        compare(changes.count, 1, "no flash while the cascade moves past the first plain lyrics");
        compare(source.current.providerId, "laterPlain");
        compare(source.cues.length, 0);
        compare(source.plainText, "la\nla", "the first provider's, though it is no longer in use");
        compare(source.plainSourceName, "Plain · test");
        compare(provider(source, "plain").plainText, "", "the provider itself forgot it");

        fakeMedia.trackKey = "t2";
        compare(source.plainText, "", "forgotten with the media");
        tryCompare(source, "plainText", "la\nla");
    }

    function test_plainLyricsGiveWayToSynced() {
        const source = createTemporaryObject(plainThenSyncedComponent, test);
        fakeMedia.url = "https://multi.test/a";
        tryCompare(source, "sourceName", "Second");
        compare(source.status, TranscriptProvider.Ready);
        compare(source.plainText, "");
    }

    function test_dummyLeavesUnidentifiedBrowserMediaAlone() {
        const source = createTemporaryObject(realDummyComponent, test);
        compare(source.current.providerId, "dummy");
        verify(source.cues.length > 0);
        // A browser's own player without Plasma Browser Integration: the popup
        // explains how to fix it instead of showing made-up lines.
        fakeMedia.needsBrowserIntegration = true;
        compare(source.current, null);
        compare(source.cues.length, 0);
        compare(source.status, TranscriptProvider.Idle);
        fakeMedia.needsBrowserIntegration = false;
        compare(source.current.providerId, "dummy");
    }

    function test_candidatesAndPinning() {
        const source = createTemporaryObject(cascadeComponent, test);
        fakeMedia.url = "https://multi.test/a";
        compare(source.candidates.map(p => p.providerId), ["empty", "cachedEmpty", "second"], "fallback only when nothing else can");
        tryCompare(source, "sourceName", "Second");

        // A pinned provider is kept even when it has nothing: no cascade.
        source.pin(provider(source, "empty"));
        compare(source.current.providerId, "empty");
        tryCompare(source, "status", TranscriptProvider.Unavailable);
        wait(50);
        compare(source.current.providerId, "empty");

        source.pin(null);
        tryCompare(source, "sourceName", "Second");

        // A pin lasts for the current media only.
        source.pin(provider(source, "cachedEmpty"));
        compare(source.current.providerId, "cachedEmpty");
        fakeMedia.trackKey = "t2";
        compare(source.pinned, null);
        compare(source.current.providerId, "empty", "automatic choice for the new media");
    }

    function test_probeListsSourcesWithTranscripts() {
        const source = createTemporaryObject(probeComponent, test);
        fakeMedia.url = "https://multi.test/a";
        tryCompare(source, "sourceName", "Second");
        // Without probing, the others don't look (no requests).
        compare(source.available.map(p => p.providerId), ["second"]);
        compare(provider(source, "third").status, TranscriptProvider.Idle);

        // The popup opens: every candidate looks; only those with a transcript are listed.
        source.probe = true;
        tryVerify(() => !source.searching);
        compare(source.available.map(p => p.providerId), ["second", "third"], "in priority order, empty ones left out");
        compare(source.current.providerId, "second", "probing does not change the source in use");
        compare(source.cues[0].text, "second");

        // Picking one from the list.
        source.pin(provider(source, "third"));
        compare(source.current.providerId, "third");
        compare(source.sourceName, "Third · test");
        compare(source.cues[0].text, "third");

        // The popup closes: the others stop and drop their results.
        source.probe = false;
        compare(source.available.map(p => p.providerId), ["third"]);
        compare(provider(source, "second").status, TranscriptProvider.Idle);
    }

    function test_candidatesFallback() {
        const source = createTemporaryObject(cascadeComponent, test);
        compare(source.candidates.map(p => p.providerId), ["fallback"]);
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

        p.setPlainOnly("a\nb", "Bare · plain");
        compare(p.status, TranscriptProvider.Unavailable);
        compare(p.plainText, "a\nb");
        compare(p.sourceName, "Bare · plain");
        compare(p.cues.length, 0);
        p.setLoading();
        compare(p.plainText, "", "dropped by the other states");
        p.setFromCache({ cues: [], label: "Bare · plain", plain: "c" });
        compare(p.status, TranscriptProvider.Unavailable);
        compare(p.plainText, "c");
        p.setFromCache({ cues: [{ start: 0, end: 1, text: "x" }], label: "Bare · en" });
        compare(p.status, TranscriptProvider.Ready);
        compare(p.plainText, "");
        p.setFromCache({ cues: [], label: "Bare" });
        compare(p.status, TranscriptProvider.Unavailable);
        compare(p.plainText, "");

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
