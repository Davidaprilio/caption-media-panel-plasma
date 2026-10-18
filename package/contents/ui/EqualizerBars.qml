import QtQuick
import org.kde.kirigami as Kirigami

// Equalizer bars. With `levels` (live audio from AudioLevels) each bar
// follows its band; without, the bars bounce to random heights while
// `running` (decorative) and settle down to a low rest level otherwise.
// Bars animate only while one of those applies, and the popup only creates
// this while it is enabled.
Item {
    id: equalizer

    property bool running: false
    // One level per bar, 0..1, or null for the decorative mode.
    property var levels: null
    property int barCount: 20
    property color color: Kirigami.Theme.highlightColor
    property real spacing: 2
    // Bars are spread evenly; a wide area gets thin bars instead of wide ones.
    property real maxBarWidth: Infinity
    // Fades the bars in from the left, for text drawn over the left side.
    property bool fadeFromLeft: true
    // Ease towards each live level (smoother, renders at the display's rate),
    // or jump to it (renders only once per audio frame).
    property bool animateLevels: true
    readonly property real slotWidth: width / barCount
    readonly property real barWidth: Math.max(2, Math.min(maxBarWidth, slotWidth - spacing))
    readonly property real restLevel: 0.12

    Repeater {
        model: equalizer.barCount

        Rectangle {
            id: bar

            required property int index
            // Bar height as a fraction of the equalizer's height.
            property real level: equalizer.restLevel

            // Next target: a random height while running, the rest level otherwise.
            // With live levels, the next frame of audio sets the target instead.
            function step() {
                if (equalizer.levels) {
                    return;
                }
                if (equalizer.running) {
                    bounce.to = 0.2 + Math.random() * 0.8;
                    bounce.duration = 150 + Math.random() * 250;
                } else if (Math.abs(level - equalizer.restLevel) > 0.001) {
                    bounce.to = equalizer.restLevel;
                    bounce.duration = 400;
                } else {
                    return;
                }
                bounce.restart();
            }

            anchors.bottom: parent.bottom
            x: index * equalizer.slotWidth + (equalizer.slotWidth - equalizer.barWidth) / 2
            width: equalizer.barWidth
            height: Math.max(width, equalizer.height * level)
            radius: width / 2
            color: equalizer.color
            // Fades in from the left, so text drawn over it stays readable.
            opacity: equalizer.fadeFromLeft ? 0.15 + 0.85 * index / Math.max(1, equalizer.barCount - 1) : 1

            Component.onCompleted: step()

            NumberAnimation {
                id: bounce
                target: bar
                property: "level"
                easing.type: Easing.OutQuad
                onFinished: bar.step()
            }

            Connections {
                target: equalizer
                function onRunningChanged() {
                    bar.step();
                }
                function onLevelsChanged() {
                    const levels = equalizer.levels;
                    if (!levels) {
                        // Audio stopped: back to the decorative mode or rest.
                        bar.step();
                        return;
                    }
                    const target = Math.max(equalizer.restLevel, levels[bar.index] || 0);
                    if (!equalizer.animateLevels) {
                        bounce.stop();
                        bar.level = target;
                        return;
                    }
                    // Eases towards the band's level over about one frame of audio.
                    bounce.to = target;
                    bounce.duration = 50;
                    bounce.restart();
                }
            }
        }
    }
}
