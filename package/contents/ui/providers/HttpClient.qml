import QtQuick

// Async HTTP for providers: one request at a time, a timeout (QML's
// XMLHttpRequest has none), and cancellation. After cancel() or a newer
// request, callbacks of older requests are never called, so a provider that
// switched to other media cannot receive a stale answer.
QtObject {
    id: http

    property int timeout: 15000

    property var _request: null
    property int _generation: 0

    property Timer _timer: Timer {
        interval: http.timeout
        onTriggered: {
            if (http._request) {
                http._request.abort();
            }
        }
    }

    function cancel() {
        ++_generation;
        _timer.stop();
        if (_request) {
            const request = _request;
            _request = null;
            request.abort();
        }
    }

    // callback(ok, responseText, httpStatus); ok means HTTP 200 with a body.
    function get(url, callback) {
        _send("GET", url, null, "", callback);
    }

    function postJson(url, object, callback) {
        _send("POST", url, JSON.stringify(object), "application/json", callback);
    }

    function _send(method, url, body, contentType, callback) {
        cancel();
        const generation = _generation;
        const request = new XMLHttpRequest();
        _request = request;
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE || generation !== _generation) {
                return;
            }
            _request = null;
            _timer.stop();
            const ok = request.status === 200 && request.responseText.length > 0;
            if (!ok) {
                console.warn("captionpanel:", method, url.split("?")[0], "failed with HTTP", request.status);
            }
            callback(ok, request.responseText, request.status);
        };
        request.open(method, url);
        if (contentType) {
            request.setRequestHeader("Content-Type", contentType);
        }
        _timer.restart();
        request.send(body);
    }
}
