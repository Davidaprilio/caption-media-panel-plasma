import QtQuick
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.mpris as Mpris

// Adapter over Plasma's MPRIS model. This is the only file that touches the
// private mpris API; if that API changes, only this file needs to follow.
Item {
    id: source

    // The player the widget follows. kmpris' multiplexer does not always
    // follow a player that starts playing (its proxy only refreshes when the
    // active row *number* changes) and may still point at a player that was
    // filtered out, so the choice is made here; see _choosePlayer().
    property var player: null
    readonly property bool hasPlayer: player !== null
    // All real players (not the multiplexer row) known to the model.
    property var _players: []
    // Changes whenever any player starts or stops playing.
    readonly property string _playingState: {
        const preferred = mpris.currentPlayer;
        const states = _players.map(p => p.playbackStatus);
        return (preferred ? preferred.playbackStatus : -1) + "|" + states.join(",");
    }

    on_PlayingStateChanged: _choosePlayer()
    // A followed player that quits turns into null.
    onPlayerChanged: {
        if (!player) {
            Qt.callLater(_choosePlayer);
        }
    }

    // Keeps the followed player while it plays; otherwise switches to one that
    // plays (the multiplexer's choice first); with nothing playing, keeps the
    // previous one as long as it exists (like Plasma's own media controller).
    function _choosePlayer() {
        const preferred = mpris.currentPlayer;
        const isPlaying = p => p && p.playbackStatus === Mpris.PlaybackStatus.Playing;
        const exists = p => p && (p === preferred || _players.indexOf(p) !== -1);
        let next = player;
        if (!isPlaying(player)) {
            if (isPlaying(preferred)) {
                next = preferred;
            } else {
                const playingOne = _players.find(isPlaying);
                next = playingOne || (exists(player) ? player : preferred);
            }
        }
        if (next !== player) {
            player = next;
        }
    }

    readonly property bool playing: hasPlayer && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property real rate: hasPlayer && player.rate > 0 ? player.rate : 1
    readonly property real lengthMs: hasPlayer ? Math.max(0, player.length / 1000) : 0
    readonly property bool canSeek: hasPlayer && player.canSeek

    // Browser media prefer the integration's metadata (see `_browser`): the
    // browser's own player sends e.g. "Song | YouTube Music" with no artist.
    readonly property string track: hasPlayer ? (_browser.title || player.track) : ""
    readonly property string artist: hasPlayer ? (_browser.artist || player.artist) : ""
    readonly property string album: hasPlayer ? (_browser.album || player.album) : ""
    readonly property string desktopEntry: hasPlayer ? player.desktopEntry : ""
    readonly property string identity: hasPlayer ? player.identity : ""
    readonly property string iconName: hasPlayer && player.iconName ? player.iconName : "media-view-subtitles-symbolic"
    // Album art / thumbnail as reported by the player ("" if none).
    readonly property string artUrl: hasPlayer ? (player.artUrl || _browser.artUrl) : ""

    // Playback controls. kmpris asserts on these in debug builds, so the
    // functions below check them first.
    readonly property bool canGoNext: hasPlayer && player.canGoNext
    readonly property bool canGoPrevious: hasPlayer && player.canGoPrevious
    readonly property bool canPlayPause: hasPlayer && (playing ? player.canPause : player.canPlay)
    // Read from player directly, so a player switch changes it once.
    readonly property string trackKey: hasPlayer ? player.identity + "\u001f" + player.track + "\u001f" + player.artist : ""

    // Page URL of the current browser media ("" if unknown). kmpris keeps
    // xesam:url to itself, so it is read straight from the Plasma Browser
    // Integration player (one busctl call per track change), together with
    // its title, artist, album and artwork (`_browser`).
    //
    // The current player may be either the browser's own MPRIS player or the
    // integration's proxy of it: kmpris does not always switch to the proxy.
    // Both are matched through the integration's kde:pid, which is the
    // browser's pid (the native player's instancePid, the proxy's kdePid).
    readonly property string url: _browser.url
    property bool urlPending: false
    // Metadata of the integration's player when it is the media we follow,
    // otherwise empty strings.
    property var _browser: _noBrowserMedia
    readonly property var _noBrowserMedia: ({ url: "", title: "", artist: "", album: "", artUrl: "" })
    readonly property string _metadataCommand: "busctl --user --json=short get-property org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata"
    property int _lookupSerial: 0

    onTrackKeyChanged: _lookupUrl()
    Component.onCompleted: _lookupUrl()

    // The previous answer stays until the new one arrives, so a title that merely
    // changes (e.g. a "(3)" notification counter) does not reload the transcript.
    function _lookupUrl() {
        if (!hasPlayer) {
            _browser = _noBrowserMedia;
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
        _browser = _matchingBrowserMedia(stdout);
        urlPending = false;
    }

    function _matchingBrowserMedia(stdout) {
        // Empty when the integration is not running.
        if (!stdout || !hasPlayer) {
            return _noBrowserMedia;
        }
        let metadata;
        try {
            metadata = JSON.parse(stdout).data;
        } catch (e) {
            console.warn("captionpanel: could not read browser media metadata:", e);
            return _noBrowserMedia;
        }
        const field = name => metadata[name] ? metadata[name].data : "";
        const pid = field("kde:pid");
        const title = field("xesam:title");
        const samePlayer = pid > 0 && (pid === player.kdePid || pid === player.instancePid);
        // The native player decorates the title ("(3) Title - YouTube",
        // "Title | YouTube Music"); a mismatch means the browser has moved on
        // and the next change looks again.
        const sameMedia = title !== "" && player.track.indexOf(title) !== -1;
        if (!samePlayer || !sameMedia) {
            return _noBrowserMedia;
        }
        const artists = metadata["xesam:artist"] ? metadata["xesam:artist"].data : [];
        return {
            url: field("xesam:url"),
            title: title,
            artist: Array.isArray(artists) ? artists.filter(a => a).join(", ") : String(artists),
            album: field("xesam:album"),
            artUrl: field("mpris:artUrl"),
        };
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

    function playPause() {
        if (!canPlayPause) {
            return;
        }
        if (playing) {
            player.Pause();
        } else {
            player.Play();
        }
    }

    function next() {
        if (canGoNext) {
            player.Next();
        }
    }

    function previous() {
        if (canGoPrevious) {
            player.Previous();
        }
    }

    function seek(ms) {
        if (canSeek) {
            player.position = Math.round(ms * 1000);
        }
    }

    Mpris.Mpris2Model {
        id: mpris
        onCurrentPlayerChanged: source._choosePlayer()
    }

    component PlayerRow: QtObject {
        required property var container
        required property bool isMultiplexer
    }

    Instantiator {
        id: playerRows
        model: mpris
        delegate: PlayerRow {}
        // Collected later: a removed row is still listed while the signal runs.
        onObjectAdded: Qt.callLater(source._collectPlayers)
        onObjectRemoved: Qt.callLater(source._collectPlayers)
    }

    function _collectPlayers() {
        const players = [];
        for (let i = 0; i < playerRows.count; ++i) {
            const row = playerRows.objectAt(i) as PlayerRow;
            if (row && !row.isMultiplexer && row.container) {
                players.push(row.container);
            }
        }
        _players = players;
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
