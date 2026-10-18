import QtQuick
import QtWebSockets
import org.kde.plasma.plasma5support as P5Support

// Live bar levels of the audio output: cava, run by code/cava_bridge.py in
// its own process, streams them over a local WebSocket. The bridge (and cava)
// only run while `active`; closing the connection makes them exit. Note that
// cava hears everything the speakers play, not just the followed player.
Item {
    id: audio

    property bool active: false
    property int bars: 20
    property int framerate: 30
    property int port: 47213
    // cava executable, passed on to the bridge (tests use a fake one).
    property string cava: "cava"

    // One level per bar, 0..1; null while nothing streams.
    property var levels: null
    // False once the bridge reported that cava is missing; stays off until restart.
    property bool available: true

    readonly property string _script: decodeURIComponent(Qt.resolvedUrl("../code/cava_bridge.py").toString().replace(/^file:\/\//, ""))
    readonly property string _command: "exec /usr/bin/python3 -I '" + _script + "' --port " + port + " --bars " + bars
        + " --framerate " + framerate + " --cava '" + cava + "'"
    property int _attempts: 0

    onActiveChanged: active ? _connect() : _disconnect()
    Component.onCompleted: {
        if (active) {
            _connect();
        }
    }

    function _connect() {
        if (!available) {
            return;
        }
        _attempts = 0;
        // Starting it again is harmless: a running bridge keeps the command
        // connected (no new process), a second one would exit at once.
        launcher.connectSource(_command);
        retry.restart();
    }

    function _disconnect() {
        retry.stop();
        socket.active = false;
        levels = null;
    }

    WebSocket {
        id: socket
        url: "ws://127.0.0.1:" + audio.port
        active: false

        onTextMessageReceived: message => {
            audio.levels = message.split(";").map(value => Math.min(1, Number(value) / 100));
        }
        onStatusChanged: {
            if (socket.status === WebSocket.Error || socket.status === WebSocket.Closed) {
                audio.levels = null;
                // The bridge may still be starting up, or just exited.
                if (audio.active && audio.available && audio._attempts < 10) {
                    retry.restart();
                }
            }
        }
    }

    Timer {
        id: retry
        interval: 300
        onTriggered: {
            ++audio._attempts;
            launcher.connectSource(audio._command);
            socket.active = false;
            socket.active = true;
        }
    }

    P5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (data["exit code"] === 2) {
                console.warn("captionpanel: cava is not installed; the equalizer stays decorative");
                audio.available = false;
                audio._disconnect();
            }
        }
    }
}
