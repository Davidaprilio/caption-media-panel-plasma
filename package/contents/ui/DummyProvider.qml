import QtQuick
import "../code/dummyTranscript.js" as Dummy

// Transcript provider contract (every future provider exposes the same shape):
//   inputs:  trackKey, title, artist, lengthMs
//   outputs: cues   - sorted array of { start, end, text } in media time (ms)
//            status - "idle" | "loading" | "ready" | "unavailable"
//            sourceName
// Heavy work (downloads, speech recognition) must live outside plasmashell;
// a provider only receives finished cues.
QtObject {
    id: provider

    property string trackKey: ""
    property string title: ""
    property string artist: ""
    property real lengthMs: 0

    property var cues: []
    readonly property string status: cues.length > 0 ? "ready" : "idle"
    readonly property string sourceName: "Dummy"

    // The dummy text is repeated to cover the whole track. Unknown length
    // (streams) gets ten minutes; very long media is capped at four hours.
    readonly property real _coverMs: lengthMs > 0 ? Math.min(lengthMs, 4 * 3600 * 1000) : 10 * 60 * 1000
    readonly property int _passes: Dummy.passesFor(_coverMs)

    // Rebuilt only when the number of passes changes, not on every length update.
    on_PassesChanged: cues = Dummy.build(_passes)
    Component.onCompleted: cues = Dummy.build(_passes)
}
