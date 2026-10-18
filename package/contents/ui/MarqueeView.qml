import QtQuick
import org.kde.plasma.components as PlasmaComponents3

// Single line that scrolls horizontally, but only when the text does not fit.
// The scroll speed is raised when needed so the whole line is shown before the
// cue ends. Nothing animates when the text fits or playback is paused.
Item {
    id: marquee

    property string text: ""
    property bool active: false
    property bool playing: false
    property real cueDurationMs: 0
    property int minimumSpeed: 40   // px/s
    property font textFont
    property int horizontalAlignment: Text.AlignLeft

    readonly property int startPause: 800
    readonly property int endPause: 400
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    readonly property real _speed: {
        const available = (cueDurationMs - startPause - endPause) / 1000;
        const needed = available > 0 ? overflow / available : 0;
        return Math.max(minimumSpeed, needed);
    }

    clip: true

    function _restart() {
        scroll.stop();
        label.x = 0;
        if (overflow > 0 && text.length > 0) {
            scroll.start();
            scroll.paused = !playing;
        }
    }

    onTextChanged: _restart()
    onOverflowChanged: _restart()
    onPlayingChanged: {
        if (scroll.running) {
            scroll.paused = !playing;
        }
    }

    PlasmaComponents3.Label {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        // Aligned like the lyric view while it fits; scrolls from the left otherwise.
        width: marquee.overflow > 0 ? implicitWidth : marquee.width
        text: marquee.text
        font: marquee.textFont
        maximumLineCount: 1
        textFormat: Text.PlainText
        horizontalAlignment: marquee.horizontalAlignment
        opacity: marquee.active ? 1 : 0.45
    }

    SequentialAnimation {
        id: scroll
        PauseAnimation {
            duration: marquee.startPause
        }
        NumberAnimation {
            target: label
            property: "x"
            to: -marquee.overflow
            duration: marquee.overflow / marquee._speed * 1000
        }
    }
}
