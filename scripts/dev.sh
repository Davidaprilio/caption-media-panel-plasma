#!/usr/bin/env bash
# Development helper for the Caption Media Panel plasmoid.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/package"
ID="com.deptechdigital.captionpanel"
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
    logs) journalctl --user -f -o cat | grep --line-buffered -iE "captionpanel|caption media|qml" ;;
    *) usage; exit 1 ;;
esac
