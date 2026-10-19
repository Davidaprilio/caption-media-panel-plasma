#!/usr/bin/env bash
# Development helper for the Caption Media Panel plasmoid.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/package"
# Plugin id and version come from metadata.json.
meta() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["KPlugin"][sys.argv[2]])' "$PKG/metadata.json" "$1"
}
ID="$(meta Id)"
QMLLINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

  install   Install the widget for the current user (or upgrade if present)
  remove    Uninstall the widget
  restart   Restart plasmashell so the panel picks up changes
  reload    install + restart
  view      Run the widget in plasmoidviewer (needs plasma-sdk)
  lint      Run qmllint over all QML files
  package   Build dist/caption-media-panel-<version>.plasmoid (for the KDE Store)
  logs      Follow plasmashell logs related to this widget
EOF
}

install_pkg() {
    if kpackagetool6 -t Plasma/Applet -s "$ID" >/dev/null 2>&1; then
        kpackagetool6 -t Plasma/Applet -u "$PKG"
    else
        kpackagetool6 -t Plasma/Applet -i "$PKG"
    fi
}

# A .plasmoid is a zip of package/ with metadata.json at its root.
package_pkg() {
    local out="$ROOT/dist/caption-media-panel-$(meta Version).plasmoid"
    mkdir -p "$ROOT/dist"
    rm -f "$out"
    python3 - "$PKG" "$out" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
    for directory, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")
        for name in sorted(files):
            if not name.endswith(".pyc"):
                path = os.path.join(directory, name)
                archive.write(path, os.path.relpath(path, src))
PY
    echo "$out"
}

restart_shell() {
    systemctl --user restart plasma-plasmashell.service
}

case "${1:-}" in
    install) install_pkg ;;
    remove) kpackagetool6 -t Plasma/Applet -r "$ID" ;;
    restart) restart_shell ;;
    reload) install_pkg && restart_shell ;;
    view)
        command -v plasmoidviewer >/dev/null || { echo "plasmoidviewer not found: sudo pacman -S plasma-sdk" >&2; exit 1; }
        plasmoidviewer -a "$PKG" -f horizontal -l topedge
        ;;
    lint)
        "$QMLLINT" -I /usr/lib/qt6/qml "$PKG"/contents/ui/*.qml "$PKG"/contents/config/*.qml
        ;;
    package) package_pkg ;;
    logs) journalctl --user -f -o cat | grep --line-buffered -iE "captionpanel|caption media|qml" ;;
    *) usage; exit 1 ;;
esac
