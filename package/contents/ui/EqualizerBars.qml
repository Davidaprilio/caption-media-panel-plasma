import QtQuick
import org.kde.kirigami as Kirigami

// Decorative equalizer: bars bouncing to random heights while `running`,
// settling down to a low rest level otherwise. It does not follow the real
// audio (that would need audio capture inside plasmashell). Bars animate only
// while running, and the popup only creates this while it is enabled.
Item {
    id: equalizer

    property bool running: false
    property int barCount: 20
    property color color: Kirigami.Theme.highlightColor
    property real spacing: 2
    readonly property real barWidth: Math.max(2, (width - spacing * (barCount - 1)) / barCount)
    readonly property real restLevel: 0.12

    Repeater {
        model: equalizer.barCount

        Rectangle {
            id: bar

            required property int index
            // Bar height as a fraction of the equalizer's height.
            property real level: equalizer.restLevel

            // Next target: a random height while running, the rest level otherwise.
            function step() {
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
            x: index * (equalizer.barWidth + equalizer.spacing)
            width: equalizer.barWidth
            height: Math.max(width, equalizer.height * level)
            radius: width / 2
            color: equalizer.color
            // Fades in from the left, so text drawn over it stays readable.
            opacity: 0.15 + 0.85 * index / Math.max(1, equalizer.barCount - 1)

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
            }
        }
    }
}
