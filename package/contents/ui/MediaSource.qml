import QtQuick
import org.kde.plasma.private.mpris as Mpris

// Adapter over Plasma's MPRIS model. This is the only file that touches the
// private mpris API; if that API changes, only this file needs to follow.
Item {
    id: source

    readonly property var player: mpris.currentPlayer
    readonly property bool hasPlayer: player !== null

    readonly property bool playing: hasPlayer && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property real rate: hasPlayer && player.rate > 0 ? player.rate : 1
    readonly property real lengthMs: hasPlayer ? Math.max(0, player.length / 1000) : 0
    readonly property bool canSeek: hasPlayer && player.canSeek

    readonly property string track: hasPlayer ? player.track : ""
    readonly property string artist: hasPlayer ? player.artist : ""
    readonly property string identity: hasPlayer ? player.identity : ""
    readonly property string iconName: hasPlayer && player.iconName ? player.iconName : "media-view-subtitles-symbolic"
    readonly property string trackKey: hasPlayer ? identity + "\u001f" + track + "\u001f" + artist : ""

    // Emitted whenever the player reports a fresh position (seek, poll reply, ...).
    signal positionUpdated(real ms)

    // Reads the player directly: a binding on player.position could still hold
    // the previous value while positionChanged handlers run.
    function positionMs() {
        // MPRIS reports microseconds.
        return hasPlayer ? player.position / 1000 : 0;
    }

    // Asks the player for its current position; the answer arrives as positionUpdated().
    function requestPositionUpdate() {
        if (hasPlayer) {
            player.updatePosition();
        }
    }

    function seek(ms) {
        if (canSeek) {
            player.position = Math.round(ms * 1000);
        }
    }

    Mpris.Mpris2Model {
        id: mpris
    }

    Connections {
        target: source.player
        ignoreUnknownSignals: true

        function onPositionChanged() {
            source.positionUpdated(source.positionMs());
        }
    }
}
