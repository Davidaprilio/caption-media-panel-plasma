import QtQuick
import org.kde.plasma.plasma5support as P5Support
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

    // Page URL of the current browser media ("" if unknown). kmpris keeps
    // xesam:url to itself, so it is read straight from the Plasma Browser
    // Integration player (one busctl call per track change).
    //
    // The current player may be either the browser's own MPRIS player or the
    // integration's proxy of it: kmpris does not always switch to the proxy.
    // Both are matched through the integration's kde:pid, which is the
    // browser's pid (the native player's instancePid, the proxy's kdePid).
    property string url: ""
    property bool urlPending: false
    readonly property string _metadataCommand: "busctl --user --json=short get-property org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata"
    property int _lookupSerial: 0

    onTrackKeyChanged: _lookupUrl()
    Component.onCompleted: _lookupUrl()

    // The previous URL stays until the answer arrives, so a title that merely
    // changes (e.g. a "(3)" notification counter) does not reload the transcript.
    function _lookupUrl() {
        if (!hasPlayer) {
            url = "";
            urlPending = false;
            return;
        }
        urlPending = true;
        // A unique shell comment, so a lookup still in flight never swallows this one.
        urlReader.connectSource(_metadataCommand + " # " + (++_lookupSerial));
    }

    function _applyMetadata(sourceName, stdout) {
        // Only the newest lookup counts.
        if (!sourceName.endsWith("# " + _lookupSerial)) {
            return;
        }
        // URL first: a moment with neither URL nor pending flag would let the
        // fallback provider flash in.
        url = _matchingUrl(stdout);
        urlPending = false;
    }

    function _matchingUrl(stdout) {
        // Empty when the integration is not running.
        if (!stdout || !hasPlayer) {
            return "";
        }
        let metadata;
        try {
            metadata = JSON.parse(stdout).data;
        } catch (e) {
            console.warn("captionpanel: could not read browser media metadata:", e);
            return "";
        }
        const field = name => metadata[name] ? metadata[name].data : "";
        const pid = field("kde:pid");
        const title = field("xesam:title");
        const samePlayer = pid > 0 && (pid === player.kdePid || pid === player.instancePid);
        // The native player decorates the title ("(3) Title - YouTube"); a
        // mismatch means the browser has moved on and the next change looks again.
        const sameMedia = title !== "" && track.indexOf(title) !== -1;
        return samePlayer && sameMedia ? field("xesam:url") : "";
    }

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

    P5Support.DataSource {
        id: urlReader
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            source._applyMetadata(sourceName, data["stdout"]);
        }
    }

    Connections {
        target: source.player
        ignoreUnknownSignals: true

        function onPositionChanged() {
            source.positionUpdated(source.positionMs());
        }
    }
}
