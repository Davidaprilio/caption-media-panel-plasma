#!/usr/bin/python3
"""Minimal MPRIS player for testing the widget without real media.

It "plays" a silent track on a wall clock and runs an optional script of
actions, e.g.:

    tests/fake_mpris_player.py --length 600 --script "5:pause,7:play,9:seek=120,14:quit"

Actions: pause, play, seek=<seconds>, rate=<float>, track=<title>, quit.
"""
import argparse
import time

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
PATH = "/org/mpris/MediaPlayer2"


class FakePlayer(dbus.service.Object):
    def __init__(self, bus, length_s, title):
        super().__init__(bus, PATH)
        self.length_us = int(length_s * 1_000_000)
        self.title = title
        self.track_no = 1
        self.status = "Playing"
        self.rate = 1.0
        self.base_pos_us = 0
        self.base_ts = time.monotonic()

    def position_us(self):
        if self.status != "Playing":
            return self.base_pos_us
        elapsed = time.monotonic() - self.base_ts
        return min(self.length_us, self.base_pos_us + int(elapsed * self.rate * 1_000_000))

    def rebase(self, pos_us=None):
        self.base_pos_us = self.position_us() if pos_us is None else pos_us
        self.base_ts = time.monotonic()

    def metadata(self):
        return dbus.Dictionary({
            "mpris:trackid": dbus.ObjectPath(f"/org/mpris/MediaPlayer2/track/{self.track_no}"),
            "mpris:length": dbus.Int64(self.length_us),
            "xesam:title": self.title,
            "xesam:artist": dbus.Array(["Caption Test"], signature="s"),
        }, signature="sv")

    def player_props(self):
        return {
            "PlaybackStatus": self.status,
            "Rate": dbus.Double(self.rate),
            "Metadata": self.metadata(),
            "Position": dbus.Int64(self.position_us()),
            "MinimumRate": dbus.Double(0.25),
            "MaximumRate": dbus.Double(4.0),
            "CanGoNext": False,
            "CanGoPrevious": False,
            "CanPlay": True,
            "CanPause": True,
            "CanSeek": True,
            "CanControl": True,
            "Volume": dbus.Double(1.0),
            "LoopStatus": "None",
            "Shuffle": False,
        }

    def root_props(self):
        return {
            "Identity": "Caption Test Player",
            "DesktopEntry": "",
            "CanQuit": True,
            "CanRaise": False,
            "HasTrackList": False,
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        }

    def changed(self, **props):
        self.PropertiesChanged(PLAYER_IFACE, props, [])

    # --- actions -------------------------------------------------------
    def set_status(self, status):
        self.rebase()
        self.status = status
        self.changed(PlaybackStatus=status)

    def set_rate(self, rate):
        self.rebase()
        self.rate = rate
        self.changed(Rate=dbus.Double(rate))

    def seek_to(self, pos_us):
        self.rebase(max(0, min(self.length_us, pos_us)))
        self.Seeked(dbus.Int64(self.base_pos_us))

    def set_track(self, title):
        self.title = title
        self.track_no += 1
        self.rebase(0)
        self.changed(Metadata=self.metadata())

    # --- org.freedesktop.DBus.Properties --------------------------------
    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return self.GetAll(iface)[prop]

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        if iface == PLAYER_IFACE:
            return self.player_props()
        if iface == ROOT_IFACE:
            return self.root_props()
        return {}

    @dbus.service.method(PROPS_IFACE, in_signature="ssv")
    def Set(self, iface, prop, value):
        if iface == PLAYER_IFACE and prop == "Rate":
            self.set_rate(float(value))

    @dbus.service.signal(PROPS_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    # --- org.mpris.MediaPlayer2 -----------------------------------------
    @dbus.service.method(ROOT_IFACE)
    def Raise(self):
        pass

    @dbus.service.method(ROOT_IFACE)
    def Quit(self):
        loop.quit()

    # --- org.mpris.MediaPlayer2.Player ----------------------------------
    @dbus.service.signal(PLAYER_IFACE, signature="x")
    def Seeked(self, position):
        print(f"seeked to {position / 1e6:.2f}s", flush=True)

    @dbus.service.method(PLAYER_IFACE)
    def Play(self):
        self.set_status("Playing")

    @dbus.service.method(PLAYER_IFACE)
    def Pause(self):
        self.set_status("Paused")

    @dbus.service.method(PLAYER_IFACE)
    def PlayPause(self):
        self.set_status("Paused" if self.status == "Playing" else "Playing")

    @dbus.service.method(PLAYER_IFACE)
    def Stop(self):
        self.set_status("Stopped")

    @dbus.service.method(PLAYER_IFACE)
    def Next(self):
        pass

    @dbus.service.method(PLAYER_IFACE)
    def Previous(self):
        pass

    @dbus.service.method(PLAYER_IFACE, in_signature="x")
    def Seek(self, offset):
        self.seek_to(self.position_us() + offset)

    @dbus.service.method(PLAYER_IFACE, in_signature="ox")
    def SetPosition(self, track_id, position):
        self.seek_to(position)


def run_action(player, action):
    name, _, arg = action.partition("=")
    print(f"[{time.monotonic() - started:6.2f}s] {action}", flush=True)
    if name == "pause":
        player.set_status("Paused")
    elif name == "play":
        player.set_status("Playing")
    elif name == "seek":
        player.seek_to(int(float(arg) * 1_000_000))
    elif name == "rate":
        player.set_rate(float(arg))
    elif name == "track":
        player.set_track(arg)
    elif name == "quit":
        loop.quit()
    return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--length", type=float, default=600, help="track length in seconds")
    parser.add_argument("--title", default="Caption test track")
    parser.add_argument("--script", default="", help="comma separated <seconds>:<action> list")
    args = parser.parse_args()

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(f"{ROOT_IFACE}.captiontest", bus)
    player = FakePlayer(bus, args.length, args.title)
    loop = GLib.MainLoop()
    started = time.monotonic()

    for step in filter(None, args.script.split(",")):
        at, _, action = step.partition(":")
        GLib.timeout_add(int(float(at) * 1000), run_action, player, action)

    print("fake player running as org.mpris.MediaPlayer2.captiontest", flush=True)
    loop.run()
