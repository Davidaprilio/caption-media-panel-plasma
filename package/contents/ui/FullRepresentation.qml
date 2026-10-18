import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "../code/cues.js" as Cues
import "../code/youtube.js" as YouTube
import "providers"

// Popup with the whole transcript. Plasma creates it on first open only.
PlasmaExtras.Representation {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.preferredHeight: Kirigami.Units.gridUnit * 26

    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        // A single child: the heading only sizes itself from its content when
        // there is exactly one.
        Item {
            anchors.fill: parent
            implicitWidth: headerRow.implicitWidth
            implicitHeight: headerRow.implicitHeight

            // Background of the right half; declared first, so the title, info
            // and buttons are drawn on top of it.
            Loader {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: parent.width * 0.5
                active: Plasmoid.configuration.popupEqualizer
                sourceComponent: EqualizerBars {
                    // Live audio (shared with the panel) when available, decorative otherwise.
                    levels: root.audioLevels.levels
                    // Animates only while it can be seen and something plays.
                    running: root.popupEqualizerShown && root.clock.playing && root.animationsEnabled
                    opacity: 0.35
                }
            }

            RowLayout {
                id: headerRow
                anchors.fill: parent
                spacing: Kirigami.Units.largeSpacing

                // Album art or video thumbnail; the player's icon when there is none.
                Item {
                    id: thumbnail

                    // Browsers' own MPRIS players send no artwork for YouTube; its
                    // thumbnail can be built from the video id.
                    readonly property string source: root.media.artUrl || YouTube.thumbnailUrl(root.media.url)

                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    Layout.alignment: Qt.AlignVCenter

                    Kirigami.ShadowedImage {
                        id: art
                        anchors.fill: parent
                        source: thumbnail.source
                        visible: status === Image.Ready
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        // Decoded at display size, not at the artwork's full resolution.
                        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                        radius: Kirigami.Units.cornerRadius
                        color: "transparent"
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.large
                        height: width
                        visible: !art.visible
                        source: root.media.iconName
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 4
                        elide: Text.ElideRight
                        text: root.media.hasPlayer ? (root.media.track || root.media.identity) : (root.demo ? i18n("Demo") : i18n("No media playing"))
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.7
                        visible: text.length > 0
                        text: {
                            const parts = [];
                            if (root.media.artist) {
                                parts.push(root.media.artist);
                            }
                            if (root.media.identity && root.media.track) {
                                parts.push(root.media.identity);
                            }
                            parts.push(i18n("Source: %1", root.transcript.sourceName));
                            return parts.join(" · ");
                        }
                    }

                    RowLayout {
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        spacing: 0
                        visible: root.media.hasPlayer

                        PlasmaComponents3.ToolButton {
                            icon.name: LayoutMirroring.enabled ? "media-skip-forward" : "media-skip-backward"
                            text: i18n("Previous")
                            display: PlasmaComponents3.AbstractButton.IconOnly
                            enabled: root.media.canGoPrevious
                            onClicked: root.media.previous()

                            PlasmaComponents3.ToolTip.text: text
                            PlasmaComponents3.ToolTip.visible: hovered
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        PlasmaComponents3.ToolButton {
                            icon.name: root.media.playing ? "media-playback-pause" : "media-playback-start"
                            text: root.media.playing ? i18n("Pause") : i18n("Play")
                            display: PlasmaComponents3.AbstractButton.IconOnly
                            enabled: root.media.canPlayPause
                            onClicked: root.media.playPause()

                            PlasmaComponents3.ToolTip.text: text
                            PlasmaComponents3.ToolTip.visible: hovered
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        PlasmaComponents3.ToolButton {
                            icon.name: LayoutMirroring.enabled ? "media-skip-backward" : "media-skip-forward"
                            text: i18n("Next")
                            display: PlasmaComponents3.AbstractButton.IconOnly
                            enabled: root.media.canGoNext
                            onClicked: root.media.next()

                            PlasmaComponents3.ToolTip.text: text
                            PlasmaComponents3.ToolTip.visible: hovered
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }
            }
        }
    }

    contentItem: PlasmaComponents3.ScrollView {
        id: scrollView

        ListView {
            id: transcript

            readonly property bool seekable: root.media.canSeek || root.demo
            readonly property int animationDuration: Kirigami.Units.longDuration > 0 ? Plasmoid.configuration.animationDuration : 0
            // Far seeks (and opening the popup) jump instead of sliding past every line.
            property bool _jumping: true

            // Moves the highlight to index and keeps it centred. The view's own
            // highlight handling is not used, so the slide can be eased.
            function showIndex(index, jump) {
                _jumping = jump || animationDuration === 0 || currentIndex < 0 || Math.abs(index - currentIndex) > 3;
                currentIndex = index;
                // Nothing to scroll while the popup is closed, or while the user scrolls.
                if (index < 0 || !root.expanded || moving) {
                    return;
                }
                const from = contentY;
                positionViewAtIndex(index, ListView.Center);
                if (_jumping) {
                    scrollAnimation.stop();
                    return;
                }
                const to = contentY;
                contentY = from;
                scrollAnimation.to = to;
                scrollAnimation.restart();
            }

            // Reads the index when it runs, not when it is scheduled.
            function jumpToCurrent() {
                showIndex(root.clock.currentIndex, true);
            }

            model: root.live ? root.transcript.cues : []
            clip: true
            reuseItems: true
            highlightFollowsCurrentItem: false
            highlightRangeMode: ListView.NoHighlightRange

            onCountChanged: Qt.callLater(jumpToCurrent)
            Component.onCompleted: jumpToCurrent()

            Connections {
                target: root.clock
                function onCurrentIndexChanged() {
                    transcript.showIndex(root.clock.currentIndex, false);
                }
            }
            Connections {
                target: root
                function onExpandedChanged() {
                    if (root.expanded) {
                        transcript.jumpToCurrent();
                    }
                }
            }

            NumberAnimation {
                id: scrollAnimation
                target: transcript
                property: "contentY"
                duration: transcript.animationDuration * 1.6
                easing.type: Easing.OutCubic
            }

            highlight: PlasmaExtras.Highlight {
                width: transcript.width
                y: transcript.currentItem ? transcript.currentItem.y : 0
                height: transcript.currentItem ? transcript.currentItem.height : 0
                visible: transcript.currentItem !== null

                Behavior on y {
                    enabled: !transcript._jumping
                    NumberAnimation {
                        duration: transcript.animationDuration
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on height {
                    enabled: !transcript._jumping
                    NumberAnimation {
                        duration: transcript.animationDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            delegate: PlasmaComponents3.ItemDelegate {
                id: row

                required property int index
                required property var modelData

                width: ListView.view.width
                hoverEnabled: transcript.seekable
                onClicked: root.seekTo(modelData.start)

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignTop
                        text: Cues.formatTime(row.modelData.start)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: row.modelData.text
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        // Opacity only: switching to bold would reflow the line. Short
                        // gaps between cues are ignored here so the line does not blink.
                        opacity: row.index === transcript.currentIndex ? 1 : 0.6

                        Behavior on opacity {
                            enabled: transcript.animationDuration > 0
                            OpacityAnimator {
                                duration: transcript.animationDuration
                            }
                        }
                    }
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: transcript.count === 0
                icon.name: "media-view-subtitles-symbolic"
                text: {
                    if (!root.live) {
                        return i18n("Nothing is playing");
                    }
                    return root.transcript.status === TranscriptProvider.Loading ? i18n("Loading transcript…") : i18n("No transcript for this media");
                }
                explanation: root.live ? "" : i18n("Start a media player to see its transcript here.")
            }
        }
    }
}
