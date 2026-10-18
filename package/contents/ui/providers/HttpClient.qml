import QtQuick

// Async HTTP for providers: one request at a time, a timeout (QML's
// XMLHttpRequest has none), retries for "busy" answers, and cancellation.
// After cancel() or a newer request, callbacks of older requests are never
// called, so a provider that switched to other media cannot receive a stale
// answer.
QtObject {
    id: http

    property int timeout: 15000
    // Extra headers for every request, e.g. { "User-Agent": "app/1.0" }.
    property var headers: ({})
    // How often a request answered with 503/429 is retried, waiting for
    // Retry-After (1-5 s) in between. get()/postJson() can override it.
    property int retries: 0

    property var _request: null
    // The request waiting for its retry.
    property var _retryJob: null
    property int _generation: 0

    property Timer _timer: Timer {
        interval: http.timeout
        onTriggered: {
            if (http._request) {
                http._request.abort();
            }
        }
    }

    property Timer _retryTimer: Timer {
        onTriggered: {
            const job = http._retryJob;
            http._retryJob = null;
            if (job && job.generation === http._generation) {
                http._start(job);
            }
        }
    }

    function cancel() {
        ++_generation;
        _timer.stop();
        _retryTimer.stop();
        _retryJob = null;
        if (_request) {
            const request = _request;
            _request = null;
            request.abort();
        }
    }

    // callback(ok, responseText, httpStatus); ok means HTTP 200 with a body.
    function get(url, callback, retryCount) {
        _send("GET", url, null, "", callback, retryCount);
    }

    function postJson(url, object, callback, retryCount) {
        _send("POST", url, JSON.stringify(object), "application/json", callback, retryCount);
    }

    function _send(method, url, body, contentType, callback, retryCount) {
        cancel();
        _start({
            method: method,
            url: url,
            body: body,
            contentType: contentType,
            callback: callback,
            retriesLeft: retryCount === undefined ? retries : retryCount,
            generation: _generation,
        });
    }

    function _start(job) {
        const request = new XMLHttpRequest();
        _request = request;
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE || job.generation !== _generation) {
                return;
            }
            _request = null;
            _timer.stop();
            if ((request.status === 503 || request.status === 429) && job.retriesLeft > 0) {
                --job.retriesLeft;
                const wait = parseInt(request.getResponseHeader("Retry-After"), 10);
                _retryTimer.interval = Math.min(5, Math.max(1, wait || 1)) * 1000;
                _retryJob = job;
                _retryTimer.restart();
                return;
            }
            const ok = request.status === 200 && request.responseText.length > 0;
            if (!ok) {
                console.warn("captionpanel:", job.method, job.url.split("?")[0], "failed with HTTP", request.status);
            }
            job.callback(ok, request.responseText, request.status);
        };
        request.open(job.method, job.url);
        for (const name in headers) {
            request.setRequestHeader(name, headers[name]);
        }
        if (job.contentType) {
            request.setRequestHeader("Content-Type", job.contentType);
        }
        _timer.restart();
        request.send(job.body);
    }
}
