import QtQuick
import QtQuick.Effects
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Ticker: the active line, with the next one waiting on its right in a muted
// tone, so a singer sees what comes next. The waiting line gets a fixed slot
// (nextMaxWidth); longer text fades out at the end of it. When the next cue
// starts, the strip slides left until that line takes the active place, its
// faded tail is revealed on the way, and the line after it rides in from the
// right into the slot. Alignment applies to the active line
// plus the slot, so the active line's position does not depend on the length
// of the next one. An active line wider than the view scrolls within its cue
// first. Three labels at most (the third only during a slide), and nothing
// animates between those moments or while paused.
Item {
    id: marquee

    property var cues: []
    // The clock's current cue index (-1 before the first one).
    property int index: -1
    // False between two cues.
    property bool active: false
    property bool playing: false
    property real rate: 1
    property int minimumSpeed: 40   // px/s
    property int animationDuration: 250
    property font textFont
    property int horizontalAlignment: Text.AlignLeft

    // Space between the active and the next line.
    property real gap: Kirigami.Units.gridUnit
    // Width of the waiting line's slot; longer text fades out at its end.
    property real nextMaxWidth: 100
    // At most 40% of the slot, so a narrow slot still shows some solid text.
    readonly property real fadeWidth: Math.min(Kirigami.Units.gridUnit * 3, nextMaxWidth * 0.4)
    readonly property real mutedOpacity: 0.4
    readonly property int startPause: 800
    readonly property int endPause: 400
    readonly property int slideDuration: animationDuration * 1.5

    // Index shown in `current`, and the one a running slide moves to.
    property int _shown: -1
    property int _slidingTo: -1
    property bool _sliding: false
    // Set while labels are swapped after a slide, so the swap itself does not animate.
    property bool _swapping: false

    clip: true

    function _text(i) {
        return i >= 0 && i < cues.length ? cues[i].text : "";
    }

    // Where the strip starts for an active line of the given width: the line
    // plus the next line's slot is aligned as a whole.
    function _anchorX(activeWidth) {
        const free = width - (activeWidth + gap + nextMaxWidth);
        if (free <= 0 || horizontalAlignment === Text.AlignLeft) {
            return 0;
        }
        return horizontalAlignment === Text.AlignHCenter ? free / 2 : free;
    }

    // Puts `i` in place without animation.
    function _show(i) {
        slide.stop();
        scroll.stop();
        _swapping = true;
        _sliding = false;
        _shown = i;
        current.text = _text(i);
        nextBox.text = _text(i + 1);
        strip.x = _anchorX(current.implicitWidth);
        _swapping = false;
        _startScroll();
    }

    function _follow() {
        if (slide.running) {
            // A cue went by faster than the slide; land on it first.
            _show(_slidingTo);
        }
        if (index === _shown + 1 && nextBox.text && animationDuration > 0) {
            scroll.stop();
            _slidingTo = index;
            afterNextBox.text = _text(index + 1);
            _sliding = true;
            // Lands where _show() puts the strip after the swap.
            slide.to = _anchorX(nextBox.textWidth) - nextBox.x;
            slide.restart();
        } else if (index !== _shown) {
            _show(index);
        }
    }

    // Long active lines scroll so their end is read before the cue is over.
    function _startScroll() {
        const overflow = current.implicitWidth - width;
        if (overflow <= 0 || !playing || _shown < 0 || _shown >= cues.length) {
            return;
        }
        const cue = cues[_shown];
        const available = ((cue.end - cue.start) / rate - startPause - endPause) / 1000;
        const speed = Math.max(minimumSpeed, available > 0 ? overflow / available : 0);
        scrollMove.to = -overflow;
        scrollMove.duration = overflow / speed * 1000;
        scroll.restart();
    }

    onIndexChanged: _follow()
    onCuesChanged: _show(index)
    onPlayingChanged: {
        if (scroll.running) {
            scroll.paused = !playing;
        } else if (playing && strip.x === _anchorX(current.implicitWidth)) {
            // Started paused: the scroll has not happened yet.
            _startScroll();
        }
    }
    onWidthChanged: relayout.restart()
    onHorizontalAlignmentChanged: relayout.restart()
    onTextFontChanged: relayout.restart()
    onNextMaxWidthChanged: relayout.restart()
    Component.onCompleted: _show(index)

    // Size, alignment or font changed: recompute positions for the current cue,
    // once per event loop pass. A child Timer rather than Qt.callLater: it dies
    // with this view, while a queued callLater would still run on a destroyed one.
    Timer {
        id: relayout
        interval: 0
        onTriggered: marquee._show(marquee.index)
    }

    Item {
        id: strip
        height: parent.height

        PlasmaComponents3.Label {
            id: current
            anchors.verticalCenter: parent.verticalCenter
            font: marquee.textFont
            maximumLineCount: 1
            textFormat: Text.PlainText
            opacity: marquee._sliding ? marquee.mutedOpacity : (marquee.active ? 1 : 0.6)

            Behavior on opacity {
                enabled: !marquee._swapping && marquee.animationDuration > 0
                OpacityAnimator {
                    duration: marquee.animationDuration
                }
            }
        }

        // The waiting line, cut to its slot. While sliding in, the slot grows
        // to the full text so the faded tail is revealed.
        FadedLine {
            id: nextBox

            x: current.text ? current.implicitWidth + marquee.gap : 0
            width: marquee._sliding ? textWidth : Math.min(textWidth, marquee.nextMaxWidth)
            opacity: marquee._sliding ? 1 : marquee.mutedOpacity

            Behavior on width {
                enabled: !marquee._swapping && marquee.animationDuration > 0
                NumberAnimation {
                    duration: marquee.slideDuration
                    easing.type: Easing.OutCubic
                }
            }

            // Shorter than the slide, so it is done before the labels swap.
            Behavior on opacity {
                enabled: !marquee._swapping && marquee.animationDuration > 0
                OpacityAnimator {
                    duration: marquee.animationDuration
                }
            }
        }

        // The line after next, only during a slide: it rides in from the right
        // and ends exactly where the waiting line's slot is after the swap.
        FadedLine {
            id: afterNextBox

            x: nextBox.x + nextBox.textWidth + marquee.gap
            width: Math.min(textWidth, marquee.nextMaxWidth)
            visible: marquee._sliding && text !== ""
            opacity: marquee.mutedOpacity
        }
    }

    // A single line cut to its width; text beyond it fades out at the end.
    component FadedLine: Item {
        id: line

        property string text: ""
        readonly property real textWidth: label.implicitWidth
        readonly property real hidden: textWidth - width

        height: strip.height

        Item {
            id: box
            anchors.fill: parent
            clip: true

            // The fade needs shaders; the software renderer just cuts the text.
            layer.enabled: line.hidden > 0.5 && GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: fadeMask
                // Maps the mask's alpha linearly-ish onto the text.
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            PlasmaComponents3.Label {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: line.text
                font: marquee.textFont
                maximumLineCount: 1
                textFormat: Text.PlainText
            }
        }

        // Alpha mask: opaque, then fading out over the last part. The fade
        // shrinks as the hidden part does, so a fully revealed line ends crisp.
        Item {
            id: fadeMask
            anchors.fill: parent
            visible: false
            layer.enabled: box.layer.enabled

            Rectangle {
                id: fadeGradient

                readonly property real fade: Math.min(marquee.fadeWidth, Math.max(0, line.hidden))

                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "white"
                    }
                    GradientStop {
                        position: Math.max(0, 1 - fadeGradient.fade / Math.max(1, line.width))
                        color: "white"
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: slide
        target: strip
        property: "x"
        duration: marquee.slideDuration
        easing.type: Easing.OutCubic
        // Not emitted when stopped early; _follow() lands on the cue then.
        onFinished: marquee._show(marquee._slidingTo)
    }

    SequentialAnimation {
        id: scroll
        PauseAnimation {
            duration: marquee.startPause
        }
        NumberAnimation {
            id: scrollMove
            target: strip
            property: "x"
        }
    }
}
