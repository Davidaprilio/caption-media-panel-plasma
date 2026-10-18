import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "../code/cues.js" as Cues
import "providers"

// What lives in the panel. The width is computed once per transcript (auto)
// or fixed (manual), so line changes never cause a panel relayout.
MouseArea {
    id: compact

    readonly property var cfg: Plasmoid.configuration
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool lyricMode: cfg.displayMode === 0
    readonly property int lines: lyricMode ? Math.max(1, Math.min(5, cfg.visibleLines)) : 1
    readonly property int animationDuration: Kirigami.Units.longDuration > 0 ? cfg.animationDuration : 0
    readonly property bool showCaption: root.live && root.transcript.cues.length > 0
    readonly property string idleText: {
        if (!root.media.hasPlayer) {
            return i18n("No media playing");
        }
        return root.transcript.status === TranscriptProvider.Loading ? i18n("Loading transcript…") : i18n("No transcript");
    }

    // Font: configured size (or theme default), shrunk until all lines fit the panel.
    readonly property font baseFont: {
        const f = Qt.font(Kirigami.Theme.defaultFont);
        if (cfg.fontSize > 0) {
            f.pointSize = cfg.fontSize;
        }
        return f;
    }
    readonly property real _scale: {
        const needed = baseMetrics.height * lines;
        return !vertical && height > 0 && needed > height ? height / needed : 1;
    }
    readonly property font textFont: {
        const f = Qt.font(baseFont);
        if (baseFont.pointSize > 0) {
            f.pointSize = Math.max(6, baseFont.pointSize * _scale);
        } else {
            f.pixelSize = Math.max(8, Math.floor(baseFont.pixelSize * _scale));
        }
        return f;
    }
    readonly property real rowHeight: textMetrics.height

    property real _longestLine: 0

    readonly property real textWidth: {
        if (cfg.widthMode === 1) {
            return cfg.manualWidth;
        }
        const content = showCaption ? _longestLine : idleMetrics.advanceWidth;
        return Math.ceil(Math.max(Kirigami.Units.gridUnit * 4, Math.min(cfg.maxAutoWidth, content)));
    }

    Layout.minimumWidth: vertical ? -1 : textWidth
    Layout.preferredWidth: vertical ? -1 : textWidth
    Layout.maximumWidth: vertical ? Infinity : textWidth
    Layout.minimumHeight: vertical ? width : -1
    Layout.preferredHeight: vertical ? width : -1

    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    onClicked: root.expanded = !root.expanded

    function measureLongestLine() {
        const texts = Cues.uniqueTexts(root.transcript.cues);
        let longest = 0;
        for (let i = 0; i < texts.length; ++i) {
            measure.text = texts[i];
            longest = Math.max(longest, measure.advanceWidth);
        }
        measure.text = "";
        // A little room so the longest line is not elided by rounding.
        _longestLine = longest + Kirigami.Units.smallSpacing;
    }

    Connections {
        target: root.transcript
        function onCuesChanged() {
            compact.measureLongestLine();
        }
    }
    onTextFontChanged: measureLongestLine()
    Component.onCompleted: measureLongestLine()

    FontMetrics {
        id: baseMetrics
        font: compact.baseFont
    }
    FontMetrics {
        id: textMetrics
        font: compact.textFont
    }
    TextMetrics {
        id: measure
        font: compact.textFont
    }
    TextMetrics {
        id: idleMetrics
        font: compact.textFont
        text: compact.idleText
    }

    // Vertical panels are too narrow for text: show an icon, read in the popup.
    Kirigami.Icon {
        anchors.fill: parent
        visible: compact.vertical
        source: "media-view-subtitles-symbolic"
        active: compact.containsMouse
        opacity: root.live ? 1 : 0.5
    }

    Loader {
        id: viewLoader
        anchors.fill: parent
        active: !compact.vertical && compact.showCaption
        sourceComponent: compact.lyricMode ? lyricComponent : marqueeComponent
    }

    PlasmaComponents3.Label {
        anchors.fill: parent
        visible: !compact.vertical && !compact.showCaption
        text: compact.idleText
        font: compact.textFont
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        opacity: 0.45
    }

    Component {
        id: lyricComponent
        Item {
            LyricView {
                // Rows stay vertically centred in the panel.
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Math.min(parent.height, compact.rowHeight * compact.lines)
                cues: root.transcript.cues
                targetIndex: root.clock.currentIndex
                active: root.clock.active
                lines: compact.lines
                rowHeight: compact.rowHeight
                textFont: compact.textFont
                animationDuration: compact.animationDuration
            }
        }
    }

    Component {
        id: marqueeComponent
        MarqueeView {
            // Before the first cue, show it dimmed, like the lyric view does.
            readonly property var cue: root.clock.currentCue ?? root.transcript.cues[0]
            text: cue ? cue.text : ""
            active: root.clock.active
            playing: root.clock.playing
            cueDurationMs: cue ? (cue.end - cue.start) / root.clock.rate : 0
            minimumSpeed: compact.cfg.marqueeSpeed
            textFont: compact.textFont
        }
    }
}
