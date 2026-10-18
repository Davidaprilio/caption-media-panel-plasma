#!/usr/bin/python3
"""Streams cava's bar levels to the widget over a local WebSocket.

The widget starts this when its popup opens and closes the connection when
it hides; the bridge then stops cava and exits on its own. Only one bridge
runs per port: a second one exits at once and the widget uses the first.

Each WebSocket text message is one frame: bar levels 0-100 separated by ";".
A single select() loop with plain sockets keeps the per-frame cost tiny
(asyncio cost more CPU than cava itself), and only small built-in modules are
imported (hashlib alone would pull in OpenSSL, ~4 MB). Standard library only.

Exit codes: 0 done, 2 cava not found, 3 port already served by another bridge.
"""
import binascii
import os
import select
import signal
import socket
import sys
import time

try:
    from _sha1 import sha1  # CPython's small built-in SHA-1
except ImportError:
    from hashlib import sha1

WS_GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
# Without a client for this long, the bridge exits (longer right after start).
START_GRACE_S = 5.0
IDLE_GRACE_S = 2.0

CAVA_CONFIG = """\
[general]
bars = {bars}
framerate = {framerate}
autosens = 1
# Stops the FFT while there is no sound.
sleep_timer = 2
[input]
method = pipewire
source = auto
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
bar_delimiter = 59
frame_delimiter = 10
channels = mono
mono_option = average
"""


def text_frame(data):
    if len(data) < 126:
        return bytes([0x81, len(data)]) + data
    return bytes([0x81, 126]) + len(data).to_bytes(2, "big") + data


def handshake(request):
    """101 response for a WebSocket upgrade request, or None."""
    for line in request.split(b"\r\n"):
        name, _, value = line.partition(b":")
        if name.strip().lower() == b"sec-websocket-key":
            accept = binascii.b2a_base64(sha1(value.strip() + WS_GUID).digest(), newline=False)
            return (b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                    b"Connection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
    return None


def serve(server, cava_out):
    # socket -> request bytes while the handshake is pending, None once open.
    clients = {}
    pending = b""
    deadline = time.monotonic() + START_GRACE_S

    def drop(sock):
        clients.pop(sock, None)
        sock.close()

    while True:
        readable, _, _ = select.select([cava_out, server, *clients], [], [], 0.5)
        for source in readable:
            if source is cava_out:
                data = os.read(cava_out, 4096)
                if not data:
                    return  # cava stopped
                *frames, pending = (pending + data).split(b"\n")
                if not frames:
                    continue
                # Only the newest frame matters; older ones would only lag.
                message = text_frame(frames[-1].rstrip(b";"))
                for sock, request in list(clients.items()):
                    if request is None:
                        try:
                            if sock.send(message) != len(message):
                                drop(sock)  # too far behind
                        except OSError:
                            drop(sock)
            elif source is server:
                sock, _ = server.accept()
                sock.setblocking(False)
                clients[sock] = b""
            else:
                try:
                    data = source.recv(4096)
                except OSError:
                    data = b""
                request = clients.get(source)
                if not data:
                    drop(source)
                elif request is not None:
                    request += data
                    if b"\r\n\r\n" in request:
                        response = handshake(request)
                        if response is None:
                            drop(source)
                        else:
                            source.sendall(response)
                            clients[source] = None
                    elif len(request) > 8192:
                        drop(source)
                    else:
                        clients[source] = request
                elif data[0] & 0x0F == 0x8:
                    drop(source)  # close frame
        if clients:
            deadline = time.monotonic() + IDLE_GRACE_S
        elif time.monotonic() > deadline:
            return


def option(name, default):
    """Value after --name on the command line (argparse costs ~1 MB)."""
    args = sys.argv[1:]
    if "--" + name in args[:-1]:
        return type(default)(args[args.index("--" + name) + 1])
    return default


def which(program):
    if os.sep in program:
        return program if os.access(program, os.X_OK) else None
    for directory in os.get_exec_path():
        path = os.path.join(directory, program)
        if os.access(path, os.X_OK):
            return path
    return None


def main():
    port = option("port", 47213)
    cava = which(option("cava", "cava"))  # tests pass a fake cava
    if not cava:
        print("captionpanel: cava not found", file=sys.stderr)
        return 2
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(("127.0.0.1", port))
    except OSError:
        # Another bridge already serves this port; the widget connects to it.
        return 3
    server.listen(4)
    server.setblocking(False)

    config_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "captionpanel-cava-%d.conf" % os.getpid())
    with os.fdopen(os.open(config_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as config:
        config.write(CAVA_CONFIG.format(bars=option("bars", 20), framerate=option("framerate", 30)))
    # posix_spawn instead of subprocess (~2 MB): cava's stdout into a pipe, stderr dropped.
    read_fd, write_fd = os.pipe()
    devnull = os.open(os.devnull, os.O_WRONLY)
    pid = os.posix_spawn(cava, [cava, "-p", config_path], os.environ, file_actions=[
        (os.POSIX_SPAWN_DUP2, write_fd, 1),
        (os.POSIX_SPAWN_DUP2, devnull, 2),
        (os.POSIX_SPAWN_CLOSE, read_fd),
    ])
    os.close(write_fd)
    os.close(devnull)
    try:
        serve(server, read_fd)
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
        os.close(read_fd)
        os.unlink(config_path)
        server.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
