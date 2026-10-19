import QtQuick

// The interface every transcript service implements.
//
// A provider declares whether it can serve the current media (`canHandle`)
// and, once TranscriptSource makes it the `active` one, fills `cues` and
// `status`. Only an active or probing provider may do work (network,
// processes); a probing one runs the same way, but only its status is read.
//
// Minimal implementation:
//
//     TranscriptProvider {
//         providerId: "lrclib"
//         displayName: "LRCLIB"
//         canHandle: media !== null && media.artist !== ""
//         readonly property string _wanted: active || probing ? media.trackKey : ""
//         on_WantedChanged: Qt.callLater(load)
//         function load() { if (!_wanted) { reset(); return } setLoading(); ... setReady(cues) / setUnavailable(reason) }
//     }
//
// Metadata changes one field at a time (kmpris: the title changes before the
// length), so read `media` from a Qt.callLater'd function, not right in the
// change handler, and read current values there rather than passing them in.
//
// Then register it in TranscriptSource.providers. Heavy work (speech
// recognition, big downloads) belongs in a separate process, not here.
QtObject {
    id: provider

    enum Status {
        Idle,
        Loading,
        Ready,
        Unavailable
    }

    // --- Description, set by the implementation -------------------------

    // Stable id, used in logs.
    property string providerId: ""
    // Shown to the user as the transcript source.
    property string displayName: ""
    // A fallback is only chosen when no specialised provider can handle the media.
    property bool fallback: false
    // Lets the user (config) switch a provider off.
    property bool enabled: true

    // --- Input, wired by TranscriptSource --------------------------------

    // The current media: a MediaSource, or anything with the same members
    // (trackKey, track, artist, album, identity, desktopEntry, lengthMs, url,
    // urlPending).
    property var media: null
    // Preferred transcript languages, most wanted first (e.g. ["id", "en"]).
    property var languages: ["en"]
    // True while this provider is the one in use.
    property bool active: false
    // True while another provider is in use but the user may pick this one
    // (the popup's source picker): find out whether the media has a
    // transcript here. Only `status` is read then.
    property bool probing: false

    // --- Decision, overridden by the implementation ----------------------

    // Whether this provider can serve `media`. Keep it a cheap binding; it
    // is evaluated for every provider on every track change.
    property bool canHandle: false

    // --- Output -----------------------------------------------------------

    // Sorted, non-overlapping { start, end, text } in media time (ms).
    property var cues: []
    property int status: TranscriptProvider.Idle
    // Shown to the user, e.g. "YouTube · English (auto-generated)".
    property string sourceName: displayName
    // Lyrics without timestamps, when that is all the source has (status is
    // then Unavailable: nothing to sync). The popup shows them as a last resort.
    property string plainText: ""

    // --- Helpers for implementations --------------------------------------

    function reset() {
        _set(TranscriptProvider.Idle, [], displayName);
    }

    function setLoading() {
        _set(TranscriptProvider.Loading, [], displayName);
    }

    function setReady(newCues, label) {
        _set(newCues.length > 0 ? TranscriptProvider.Ready : TranscriptProvider.Unavailable, newCues, label || displayName);
    }

    function setUnavailable(reason) {
        console.warn("captionpanel:", providerId, "has no transcript:", reason);
        _set(TranscriptProvider.Unavailable, [], displayName);
    }

    // No synced transcript, but plain lyrics.
    function setPlainOnly(text, label) {
        _set(TranscriptProvider.Unavailable, [], label || displayName, text);
    }

    // Applies a cache entry { cues, label, plain } written with remember().
    function setFromCache(entry) {
        if (entry.cues.length === 0 && entry.plain) {
            setPlainOnly(entry.plain, entry.label);
        } else {
            setReady(entry.cues, entry.label);
        }
    }

    function _set(newStatus, newCues, label, plain) {
        cues = newCues;
        sourceName = label;
        plainText = plain || "";
        status = newStatus;
    }

    // Small in-memory cache, so going back to recent media does not refetch.
    property int cacheSize: 8
    property var _cache: ({})
    property var _cacheOrder: []

    function cached(key) {
        return _cache[key];
    }

    function remember(key, value) {
        if (!(key in _cache)) {
            _cacheOrder.push(key);
        }
        _cache[key] = value;
        while (_cacheOrder.length > cacheSize) {
            delete _cache[_cacheOrder.shift()];
        }
    }
}
