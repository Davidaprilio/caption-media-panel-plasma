import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Templates as T
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

    // Nothing synced, but unsynced lyrics were found: shown as plain text.
    readonly property bool plainShown: root.live && root.transcript.cues.length === 0 && root.transcript.plainText !== ""

    header: PlasmaExtras.PlasmoidHeading {
        // A single child: the heading only sizes itself from its content when
        // there is exactly one.
        Item {
            anchors.fill: parent
            implicitWidth: headerRow.implicitWidth
            implicitHeight: headerRow.implicitHeight

            // Ambient mode: the artwork, heavily blurred, glows out from behind
            // the thumbnail and fades away. Decoded tiny (it is blurred anyway)
            // and only re-rendered when the artwork changes; needs shaders.
            Loader {
                id: ambient
                anchors.fill: parent
                anchors.margins: -Kirigami.Units.smallSpacing
                active: Plasmoid.configuration.popupAmbient && thumbnail.source !== ""
                    && GraphicsInfo.api !== GraphicsInfo.Software
                sourceComponent: Item {
                    Image {
                        id: ambientArt
                        anchors.fill: parent
                        source: thumbnail.source
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: ambientArt
                        visible: ambientArt.status === Image.Ready
                        opacity: 0.75
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 64
                        saturation: 0.6
                        maskEnabled: true
                        maskSource: ambientGlow
                        // Maps the mask's alpha linearly-ish onto the artwork.
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    // Strongest around the thumbnail, gone towards the far side.
                    Shape {
                        id: ambientGlow
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: RadialGradient {
                                centerX: Kirigami.Units.gridUnit * 2 + Kirigami.Units.smallSpacing
                                centerY: ambientGlow.height / 2
                                centerRadius: Math.max(ambientGlow.width * 0.6, Kirigami.Units.gridUnit * 6)
                                focalX: centerX
                                focalY: centerY
                                GradientStop {
                                    position: 0
                                    color: "white"
                                }
                                GradientStop {
                                    position: 0.45
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                }
                                GradientStop {
                                    position: 1
                                    color: "transparent"
                                }
                            }
                            PathRectangle {
                                width: ambientGlow.width
                                height: ambientGlow.height
                            }
                        }
                    }
                }
            }

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
                    color: root.equalizerColor
                    opacity: Plasmoid.configuration.popupEqualizerOpacity / 100
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

    // Pinned below the transcript: where the lines come from, and the other
    // sources that can serve this media.
    footer: PlasmaExtras.PlasmoidHeading {
        position: T.ToolBar.Footer
        visible: root.live && root.transcript.candidates.length > 0

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                opacity: 0.7
                text: {
                    const transcript = root.transcript;
                    // "sc" (source) keeps the footer short.
                    if (transcript.status === TranscriptProvider.Loading) {
                        return i18nc("sc = lyrics source", "sc: loading…");
                    }
                    if (full.plainShown) {
                        return i18nc("sc = lyrics source; unsynced = lyrics without timestamps", "sc: %1 · unsynced", transcript.plainSourceName);
                    }
                    if (!transcript.current || transcript.status === TranscriptProvider.Unavailable) {
                        return i18nc("sc = lyrics source", "sc: none");
                    }
                    return i18nc("sc = lyrics source", "sc: %1", transcript.sourceName);
                }
            }

            PlasmaComponents3.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                visible: root.transcript.searching
                running: visible
            }

            // Only the sources that have lyrics for this media (looked up
            // while the popup is open); picking one pins it.
            PlasmaComponents3.ComboBox {
                id: sourcePicker

                readonly property var sources: root.transcript.available

                visible: sources.length > 0
                model: sources.map(provider => provider.sourceName || provider.displayName)
                currentIndex: sources.indexOf(root.transcript.current)
                onActivated: index => root.transcript.pin(sources[index])
            }
        }
    }

    contentItem: Item {
        PlasmaComponents3.ScrollView {
            id: scrollView

            anchors.fill: parent
            visible: !full.plainShown

            ListView {
                id: transcript

                readonly property bool seekable: root.media.canSeek || root.demo
                readonly property int animationDuration: Kirigami.Units.longDuration > 0 ? Plasmoid.configuration.animationDuration : 0
                // Far seeks (and opening the popup) jump instead of sliding past every line.
                property bool _jumping: true
                // Cleared when the user scrolls away; the follow button sets it again.
                property bool following: true
                // Where the current line is while the user reads elsewhere (the button's arrow).
                property bool currentAbove: false
                property int _scrollTarget: -1
                property bool _correcting: false

                // Moves the highlight to index and, while following, keeps it centred.
                // The view's own highlight handling is not used, so the slide can be eased.
                function showIndex(index, jump) {
                    _jumping = jump || animationDuration === 0 || currentIndex < 0 || Math.abs(index - currentIndex) > 3;
                    currentIndex = index;
                    if (!following) {
                        _updateCurrentAbove();
                    }
                    // Nothing to scroll while the popup is closed, or while the user reads elsewhere.
                    if (index < 0 || !root.expanded || !following) {
                        return;
                    }
                    // A far line that is on screen (a clicked one) still scrolls smoothly.
                    _centre(index, !_jumping || (!jump && animationDuration > 0 && _onScreen(index)), animationDuration * 1.6);
                }

                // Reads the index when it runs, not when it is scheduled.
                function jumpToCurrent() {
                    following = true;
                    showIndex(root.clock.currentIndex, true);
                }

                // The user scrolls: stop following until asked to.
                function stopFollowing() {
                    if (following && count > 0 && contentHeight > height) {
                        following = false;
                        scrollAnimation.stop();
                        _updateCurrentAbove();
                    }
                }

                // Back to the current line, smoothly however far it is, and follow it again.
                function follow() {
                    following = true;
                    if (count > 0 && root.expanded) {
                        _centre(Math.max(0, root.clock.currentIndex), animationDuration > 0, animationDuration * 2.5);
                    }
                }

                function _centre(index, animate, duration, correction) {
                    _scrollTarget = index;
                    _correcting = correction === true;
                    const from = contentY;
                    positionViewAtIndex(index, ListView.Center);
                    const to = contentY;
                    if (!animate || Math.abs(to - from) < 1) {
                        scrollAnimation.stop();
                        return;
                    }
                    contentY = from;
                    scrollAnimation.duration = duration;
                    scrollAnimation.to = to;
                    scrollAnimation.restart();
                }

                // Rows between here and a far target are only laid out on the way,
                // so wrapped ones can leave it a little off centre: glide the rest, once.
                function _landed() {
                    const item = itemAtIndex(_scrollTarget);
                    if (following && !_correcting && item && Math.abs(item.y + item.height / 2 - contentY - height / 2) >= 1) {
                        _centre(_scrollTarget, true, animationDuration, true);
                    }
                }

                function _onScreen(index) {
                    const item = itemAtIndex(index);
                    return item !== null && item.y + item.height > contentY && item.y < contentY + height;
                }

                function _updateCurrentAbove() {
                    const centre = indexAt(width / 2, contentY + height / 2);
                    currentAbove = centre !== -1 && root.clock.currentIndex < centre;
                }

                model: root.live ? root.transcript.cues : []
                clip: true
                reuseItems: true
                highlightFollowsCurrentItem: false
                highlightRangeMode: ListView.NoHighlightRange

                onCountChanged: Qt.callLater(jumpToCurrent)
                Component.onCompleted: jumpToCurrent()
                // Touch flicks. Wheel and touchpad scrolling go through Plasma's
                // wheel handler instead, which emits no movement signals (see wheelWatcher).
                onMovementStarted: stopFollowing()
                onContentYChanged: {
                    if (!following) {
                        _updateCurrentAbove();
                    }
                }

                Connections {
                    target: scrollView.T.ScrollBar.vertical
                    function onPressedChanged() {
                        if (scrollView.T.ScrollBar.vertical.pressed) {
                            transcript.stopFollowing();
                        }
                    }
                }

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
                    easing.type: Easing.OutCubic
                    onFinished: transcript._landed()
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
                    onClicked: {
                        if (transcript.seekable) {
                            root.seekTo(modelData.start);
                            // Reading elsewhere: follow again from the clicked line.
                            if (!transcript.following) {
                                transcript.follow();
                            }
                        }
                    }

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

        // Sees wheel and touchpad scrolling before Plasma's ScrollView does
        // (its wheel handler swallows the event) and lets it through.
        MouseArea {
            id: wheelWatcher
            anchors.fill: scrollView
            enabled: scrollView.visible
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                transcript.stopFollowing();
                wheel.accepted = false;
            }
        }

        // Back to the current line once the user has scrolled away.
        PlasmaComponents3.Button {
            id: followButton

            readonly property bool shown: scrollView.visible && !transcript.following

            anchors.horizontalCenter: scrollView.horizontalCenter
            anchors.bottom: scrollView.bottom
            anchors.bottomMargin: shown ? Kirigami.Units.largeSpacing : 0
            opacity: shown ? 1 : 0
            visible: opacity > 0
            enabled: shown
            // An accent pill: a themed button frame is barely visible over the text.
            Kirigami.Theme.colorSet: Kirigami.Theme.Selection
            Kirigami.Theme.inherit: false
            leftPadding: Kirigami.Units.largeSpacing * 1.5
            rightPadding: Kirigami.Units.largeSpacing * 1.5
            topPadding: Kirigami.Units.smallSpacing * 1.5
            bottomPadding: Kirigami.Units.smallSpacing * 1.5
            background: Kirigami.ShadowedRectangle {
                radius: height / 2
                color: followButton.down ? Qt.darker(Kirigami.Theme.backgroundColor, 1.15)
                    : followButton.hovered ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.1) : Kirigami.Theme.backgroundColor
                shadow.size: Kirigami.Units.largeSpacing
                shadow.yOffset: 1
                shadow.color: Qt.rgba(0, 0, 0, 0.3)
            }
            icon.name: transcript.currentAbove ? "go-up-symbolic" : "go-down-symbolic"
            icon.color: Kirigami.Theme.textColor
            text: {
                const current = root.transcript.current;
                return current && current.providerId === "youtube" ? i18n("Follow captions") : i18n("Follow lyrics");
            }
            onClicked: transcript.follow()

            Behavior on opacity {
                enabled: transcript.animationDuration > 0
                NumberAnimation {
                    duration: transcript.animationDuration
                }
            }
            Behavior on anchors.bottomMargin {
                enabled: transcript.animationDuration > 0
                NumberAnimation {
                    duration: transcript.animationDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Created only when needed.
        Loader {
            anchors.fill: parent
            active: full.plainShown
            sourceComponent: PlasmaComponents3.ScrollView {
                id: plainView

                contentWidth: availableWidth

                PlasmaComponents3.Label {
                    width: plainView.availableWidth
                    padding: Kirigami.Units.largeSpacing
                    text: root.transcript.plainText
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    lineHeight: 1.15
                }
            }
        }
    }
}
