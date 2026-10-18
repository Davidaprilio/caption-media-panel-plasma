import QtQuick
import "../../code/youtube.js" as YouTube

// YouTube videos playing in a browser (the page URL comes from Plasma Browser
// Integration). Two requests per video: player info, then the caption track.
TranscriptProvider {
    id: provider

    readonly property string videoId: media ? YouTube.videoIdFromUrl(media.url) : ""
    // The video to load: none while another provider is in use.
    readonly property string _wanted: active ? videoId : ""

    providerId: "youtube"
    displayName: "YouTube"
    canHandle: videoId !== ""

    on_WantedChanged: load(_wanted)

    property HttpClient http: HttpClient {}

    function load(id) {
        http.cancel();
        if (!id) {
            reset();
            return;
        }
        const hit = cached(id);
        if (hit) {
            setReady(hit.cues, hit.label);
            return;
        }
        setLoading();
        _fetchPlayer(id, 0);
    }

    function _fetchPlayer(id, clientIndex) {
        if (clientIndex >= YouTube.CLIENTS.length) {
            setUnavailable("no client returned caption tracks for " + id);
            return;
        }
        http.postJson(YouTube.PLAYER_URL, YouTube.playerRequest(id, YouTube.CLIENTS[clientIndex]), (ok, text) => {
            const response = ok ? _parse(text) : null;
            const track = response ? YouTube.pickTrack(response, languages) : null;
            if (track) {
                _fetchTrack(id, track);
            } else if (YouTube.isPlayable(response)) {
                // The client works; the video simply has no captions.
                setUnavailable("video " + id + " has no captions");
            } else {
                _fetchPlayer(id, clientIndex + 1);
            }
        });
    }

    function _fetchTrack(id, track) {
        http.get(YouTube.trackUrl(track), (ok, text) => {
            const json3 = ok ? _parse(text) : null;
            const newCues = json3 ? YouTube.json3ToCues(json3) : [];
            if (newCues.length === 0) {
                setUnavailable("caption track of " + id + " was empty");
                return;
            }
            const label = displayName + " · " + YouTube.trackLabel(track);
            remember(id, { cues: newCues, label: label });
            setReady(newCues, label);
        });
    }

    function _parse(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }
}
