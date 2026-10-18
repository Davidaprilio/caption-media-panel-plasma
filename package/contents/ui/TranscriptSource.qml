import QtQuick
import "providers"

// Router between transcript providers. It exposes the output of whichever
// provider is in use, so the rest of the widget only talks to this object.
// The providers themselves are registered by the user of this type (main.qml).
//
// Selection: the first enabled, non-fallback provider whose canHandle is true
// (in list order) wins; otherwise the first enabled fallback.
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

    function _choose() {
        let fallback = null;
        for (let i = 0; i < providers.length; ++i) {
            const provider = providers[i];
            if (!provider.enabled || !provider.canHandle) {
                continue;
            }
            if (!provider.fallback) {
                return provider;
            }
            fallback = fallback || provider;
        }
        // The URL may still reveal a specialised provider; don't flash the fallback meanwhile.
        return media && media.urlPending ? null : fallback;
    }

    Component.onCompleted: {
        for (let i = 0; i < providers.length; ++i) {
            const provider = providers[i];
            provider.media = Qt.binding(() => source.media);
            provider.languages = Qt.binding(() => source.languages);
            provider.active = Qt.binding(() => source.current === provider);
        }
    }
}
