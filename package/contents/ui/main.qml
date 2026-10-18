import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "providers"

// Wiring: MediaSource (MPRIS) -> CueClock <- TranscriptSource (provider
// registry), and the panel / popup views read from the clock and the transcript.
PlasmoidItem {
    id: root

    readonly property alias media: media
    readonly property alias transcript: transcript
    readonly property alias clock: clock
    readonly property alias audioLevels: audioLevels

    // Demo mode plays the dummy transcript on a local clock when no player exists.
    readonly property bool demo: !media.hasPlayer && Plasmoid.configuration.demoWhenIdle
    readonly property bool live: media.hasPlayer || demo

    // Equalizers: one behind the panel caption, one behind the popup title.
    // Both read the same AudioLevels, so cava runs once for either or both.
    readonly property bool animationsEnabled: Kirigami.Units.longDuration > 0
    readonly property bool panelEqualizerShown: Plasmoid.configuration.panelEqualizer && live
        && Plasmoid.formFactor !== PlasmaCore.Types.Vertical
    readonly property bool popupEqualizerShown: Plasmoid.configuration.popupEqualizer && expanded

    function seekTo(ms) {
        if (demo) {
            clock.sync(ms);
        } else if (media.canSeek) {
            media.seek(ms);
            // Show the new line right away; the player's Seeked reply confirms it.
            clock.sync(ms);
        }
    }

    Plasmoid.icon: "media-view-subtitles-symbolic"
    Plasmoid.status: live ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    toolTipMainText: media.hasPlayer ? (media.track || media.identity) : i18n("Caption Media Panel")
    toolTipSubText: {
        if (!live) {
            return i18n("No media playing");
        }
        const cue = clock.currentCue;
        return cue && clock.active ? cue.text : (media.artist || media.identity);
    }

    preferredRepresentation: compactRepresentation
    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    MediaSource {
        id: media
    }

    TranscriptSource {
        id: transcript
        media: root.media
        // System language first, English as the fallback.
        languages: {
            const system = Qt.locale().name.split("_")[0];
            return system === "en" ? ["en"] : [system, "en"];
        }

        // Transcript services, in priority order. To add one, implement
        // TranscriptProvider (providers/) and list it here.
        providers: [
            YouTubeProvider {},
            LrclibProvider {
                enabled: Plasmoid.configuration.lrclibEnabled
            },
            DummyProvider {
                enabled: Plasmoid.configuration.dummyForOtherMedia || root.demo
            }
        ]
    }

    AudioLevels {
        id: audioLevels
        // The panel's equalizer only needs audio while something plays; the
        // popup's while it is open.
        active: Plasmoid.configuration.equalizerFollowsAudio && root.animationsEnabled
            && ((root.panelEqualizerShown && clock.playing) || root.popupEqualizerShown)
    }

    CueClock {
        id: clock
        cues: root.live ? transcript.cues : []
        playing: media.playing || root.demo
        rate: media.hasPlayer ? media.rate : 1
        onResyncRequested: media.requestPositionUpdate()
        onFinished: {
            if (root.demo) {
                sync(0);
            }
        }
    }

    Connections {
        target: media

        function onPositionUpdated(ms) {
            clock.sync(ms);
        }
        // The stored position can be stale here; keep interpolating and ask
        // the player for the real value.
        function onPlayingChanged() {
            media.requestPositionUpdate();
        }
        function onPlayerChanged() {
            clock.sync(media.positionMs());
            media.requestPositionUpdate();
        }
        // The stored position still belongs to the previous track until the
        // player answers, so wait for that answer instead of syncing to it.
        function onTrackKeyChanged() {
            media.requestPositionUpdate();
        }
    }

    onDemoChanged: {
        if (demo) {
            clock.sync(0);
        }
    }
}
