import QtQuick
import org.kde.plasma.components as PlasmaComponents3

// Lyric-style view: the transcript is a column of lines that slides up by one
// row whenever the cue changes. Animation only runs during that slide.
ListView {
    id: list

    property var cues: []
    property int targetIndex: -1
    property bool active: false
    property int lines: 1
    property real rowHeight: 20
    property font textFont
    property int animationDuration: 250
    property int horizontalAlignment: Text.AlignLeft

    // Current line sits on the first row for 1-2 lines (upcoming line below),
    // and in the middle for 3+ (previous above, upcoming below).
    readonly property int anchorRow: Math.floor((lines - 1) / 2)
    property bool _jumping: false

    model: cues
    interactive: false
    clip: true
    reuseItems: true
    cacheBuffer: 0
    boundsBehavior: Flickable.StopAtBounds

    highlight: Item {}
    highlightFollowsCurrentItem: true
    highlightRangeMode: ListView.StrictlyEnforceRange
    preferredHighlightBegin: anchorRow * rowHeight
    preferredHighlightEnd: preferredHighlightBegin + rowHeight
    highlightMoveVelocity: -1
    // Seeks far away jump straight there instead of scrolling through every line.
    highlightMoveDuration: _jumping ? 0 : animationDuration

    onTargetIndexChanged: {
        const index = Math.max(0, targetIndex);
        _jumping = Math.abs(index - currentIndex) > 2;
        currentIndex = index;
    }
    onCuesChanged: {
        _jumping = true;
        currentIndex = Math.max(0, targetIndex);
    }

    delegate: PlasmaComponents3.Label {
        required property int index
        required property var modelData

        width: ListView.view.width
        height: list.rowHeight
        text: modelData.text
        font: list.textFont
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        horizontalAlignment: list.horizontalAlignment
        verticalAlignment: Text.AlignVCenter
        opacity: index === list.targetIndex && list.active ? 1 : 0.45

        Behavior on opacity {
            enabled: list.animationDuration > 0
            OpacityAnimator {
                duration: list.animationDuration
            }
        }
    }
}
