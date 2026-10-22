import QtQuick
import "../../code/dummyTranscript.js" as Dummy

// Placeholder transcript for media no real provider can serve, repeated to
// cover the whole track.
TranscriptProvider {
    id: provider

    // Unknown length (streams) gets ten minutes; very long media is capped at four hours.
    readonly property real _coverMs: media && media.lengthMs > 0 ? Math.min(media.lengthMs, 4 * 3600 * 1000) : 10 * 60 * 1000
    readonly property int _passes: Dummy.passesFor(_coverMs)

    providerId: "dummy"
    displayName: "Dummy"
    fallback: true
    // Not for browser media the widget cannot identify: the popup explains
    // how to fix that instead of showing made-up lines.
    canHandle: !media || !media.needsBrowserIntegration

    // Rebuilt only when the number of passes changes, not on every length update.
    on_PassesChanged: setReady(Dummy.build(_passes))
    Component.onCompleted: setReady(Dummy.build(_passes))
}
