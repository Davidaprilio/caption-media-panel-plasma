import QtQuick
import "../code/cues.js" as Cues

// Turns sparse player position reports into the index of the cue that should
// be on screen. Position is interpolated locally; a single-shot timer wakes up
// at the next cue boundary, so nothing runs between line changes and nothing
// at all runs while paused.
Item {
    id: clock

    property var cues: []
    property bool playing: false
    property real rate: 1
    property int resyncInterval: 5000

    readonly property int currentIndex: _index
    // False while between two cues (the previous line stays, dimmed).
    readonly property bool active: _active
    readonly property var currentCue: _index >= 0 && _index < cues.length ? cues[_index] : null

    // Ask the media source for a fresh position, to correct drift.
    signal resyncRequested()
    // Playback ran past the last cue.
    signal finished()

    property int _index: -1
    property bool _active: false
    property real _basePos: 0
    property real _baseTs: 0
    property bool _running: false
    property real _rate: 1

    function positionNow() {
        return _running ? _basePos + (Date.now() - _baseTs) * _rate : _basePos;
    }

    function sync(posMs) {
        _basePos = posMs;
        _baseTs = Date.now();
        _evaluate();
    }

    function _evaluate() {
        const pos = positionNow();
        const index = Cues.indexAt(cues, pos);
        _index = index;
        _active = index >= 0 && pos < cues[index].end;

        if (!_running) {
            boundaryTimer.stop();
            return;
        }
        const next = Cues.nextBoundary(cues, index, pos);
        if (next < 0) {
            boundaryTimer.stop();
            finished();
            return;
        }
        // Qt timers are coarse (~5% slack), so long waits stop a bit short and
        // a second, short wait lands on the boundary precisely.
        const remaining = (next - pos) / _rate;
        boundaryTimer.interval = Math.max(1, Math.ceil(remaining > 400 ? remaining - 150 : remaining + 2));
        boundaryTimer.restart();
    }

    onPlayingChanged: {
        const pos = positionNow();
        _running = playing;
        sync(pos);
    }
    onRateChanged: {
        const pos = positionNow();
        _rate = rate;
        sync(pos);
    }
    onCuesChanged: _evaluate()

    Component.onCompleted: {
        _running = playing;
        _rate = rate;
        _evaluate();
    }

    Timer {
        id: boundaryTimer
        repeat: false
        onTriggered: clock._evaluate()
    }

    Timer {
        interval: clock.resyncInterval
        repeat: true
        running: clock.playing && clock.cues.length > 0
        onTriggered: clock.resyncRequested()
    }
}
