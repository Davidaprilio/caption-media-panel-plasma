import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

// Wiring: MediaSource (MPRIS) -> CueClock <- transcript provider, and the
// panel / popup views read from the clock and the provider.
PlasmoidItem {
    id: root

    readonly property alias media: media
    readonly property alias provider: provider
    readonly property alias clock: clock

    // Demo mode plays the dummy transcript on a local clock when no player exists.
    readonly property bool demo: !media.hasPlayer && Plasmoid.configuration.demoWhenIdle
    readonly property bool live: media.hasPlayer || demo

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

    DummyProvider {
        id: provider
        trackKey: media.trackKey
        title: media.track
        artist: media.artist
        lengthMs: media.lengthMs
    }

    CueClock {
        id: clock
        cues: root.live ? provider.cues : []
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
