import QtQuick
import "providers"

// Router between transcript providers. It exposes the output of whichever
// provider is in use, so the rest of the widget only talks to this object.
// The providers themselves are registered by the user of this type (main.qml).
//
// Selection, in list order:
//  1. The first enabled, non-fallback provider whose canHandle is true.
//  2. If that one ends up Unavailable for this media, the next such provider
//     is tried (e.g. YouTube Music: YouTube captions, then LRCLIB lyrics).
//     When all of them are out, the last one stays (Unavailable): a fallback
//     never stands in for media a real provider claimed.
//  3. With no non-fallback provider interested, the first enabled fallback.
// The tried list starts over whenever the media (track or URL) changes.
//
// While `probe` is set (the popup is open), the other candidates look for a
// transcript too, so `available` lists every source that has one; the user
// can pin one of them. The pin is dropped with the next media.
QtObject {
    id: source

    // The current media: a MediaSource, or anything with the same members.
    property var media: null
    property var languages: ["en"]
    // Order is priority.
    property list<TranscriptProvider> providers

    readonly property TranscriptProvider current: _choose()

    readonly property var cues: current ? current.cues : []
    readonly property int status: {
        if (current) {
            return current.status;
        }
        return media && media.urlPending ? TranscriptProvider.Loading : TranscriptProvider.Idle;
    }
    readonly property string sourceName: current ? current.sourceName : ""

    // Providers that can serve the current media, in priority order: the
    // choices for pinning. Fallbacks only when nothing else can.
    readonly property var candidates: {
        const specialised = [];
        const fallbacks = [];
        for (let i = 0; i < providers.length; ++i) {
            const provider = providers[i];
            if (provider.enabled && provider.canHandle) {
                (provider.fallback ? fallbacks : specialised).push(provider);
            }
        }
        return specialised.length > 0 ? specialised : fallbacks;
    }
    // Let the other candidates find out whether they have a transcript.
    // Costs their requests, so only while someone looks (the popup).
    property bool probe: false
    // Candidates known to have a transcript for the current media, in priority order.
    readonly property var available: candidates.filter(provider => provider.status === TranscriptProvider.Ready)
    // True while some candidate is still looking.
    readonly property bool searching: candidates.some(provider => provider.status === TranscriptProvider.Loading)
    // The provider chosen by the user, or null for the automatic choice.
    property TranscriptProvider pinned: null

    function pin(provider) {
        pinned = provider;
    }

    // Providers that had nothing for the current media, in the order they gave up.
    property var _exhausted: []
    readonly property string _mediaKey: media ? media.trackKey + "\u001f" + media.url : ""

    on_MediaKeyChanged: {
        _exhausted = [];
        pinned = null;
    }

    function _choose() {
        if (pinned && pinned.enabled && pinned.canHandle) {
            return pinned;
        }
        let fallback = null;
        let lastExhausted = null;
        for (let i = 0; i < providers.length; ++i) {
            const provider = providers[i];
            if (!provider.enabled || !provider.canHandle) {
                continue;
            }
            if (provider.fallback) {
                fallback = fallback || provider;
            } else if (_exhausted.indexOf(provider) === -1) {
                return provider;
            } else if (_exhausted.indexOf(provider) > _exhausted.indexOf(lastExhausted)) {
                lastExhausted = provider;
            }
        }
        if (lastExhausted) {
            return lastExhausted;
        }
        // The URL may still reveal a specialised provider; don't flash the fallback meanwhile.
        return media && media.urlPending ? null : fallback;
    }

    // Moves on when the provider in use has nothing for this media.
    function _checkCurrent() {
        const provider = current;
        if (provider && provider.status === TranscriptProvider.Unavailable && !provider.fallback
                && _exhausted.indexOf(provider) === -1) {
            _exhausted = _exhausted.concat([provider]);
        }
    }

    // Always deferred: a provider can answer (e.g. from its cache) while
    // `current` is still notifying about the switch to it, and changing
    // _exhausted right then would be a binding loop on `current`.
    property Connections _cascade: Connections {
        target: source.current
        function onStatusChanged() {
            Qt.callLater(source._checkCurrent);
        }
    }

    onCurrentChanged: Qt.callLater(_checkCurrent)

    Component.onCompleted: {
        for (let i = 0; i < providers.length; ++i) {
            const provider = providers[i];
            provider.media = Qt.binding(() => source.media);
            provider.languages = Qt.binding(() => source.languages);
            provider.active = Qt.binding(() => source.current === provider);
            provider.probing = Qt.binding(() => source.probe && source.current !== provider && source.candidates.indexOf(provider) !== -1);
        }
    }
}
