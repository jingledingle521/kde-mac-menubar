#!/usr/bin/env bash
# Install the Mac menu bar for KDE Plasma 6 for the current user: the Menu
# Bar widget, and the helper it needs (the global-menu registrar and the
# D-Bus menu proxy the widget reads apps' menus through).
#
#   ./install.sh            widget + helper
#   ./install.sh --vivaldi  ...and Vivaldi's menus too (see bridge/install-vivaldi.sh)
#
# Then add "Menu Bar" to your top panel (right-click the panel ›
# Add Widgets…) in place of the Application Menu / Global Menu widgets.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
config=${XDG_CONFIG_HOME:-$HOME/.config}

vivaldi=0
for arg in "$@"; do
    case $arg in
        --vivaldi) vivaldi=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

python3 -c 'import gi' 2>/dev/null || { echo "The helper needs PyGObject (Fedora: python3-gobject, Debian/Ubuntu: python3-gi)." >&2; exit 1; }

echo "Installing the Menu Bar widget…"
kpackagetool6 -t Plasma/Applet --upgrade "$here/menubar" >/dev/null 2>&1 \
    || kpackagetool6 -t Plasma/Applet --install "$here/menubar"

echo "Installing the menu helper…"
mkdir -p "$HOME/.local/bin" "$config/systemd/user"
install -m 755 "$here/bridge/vivaldi-menu-bridge" "$HOME/.local/bin/vivaldi-menu-bridge"
cp "$here/bridge/vivaldi-menu-bridge.service" "$config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now vivaldi-menu-bridge.service
systemctl --user restart vivaldi-menu-bridge.service

if [ $vivaldi = 1 ]; then
    "$here/bridge/install-vivaldi.sh"
fi

cat <<MSG

Installed. Add "Menu Bar" to your top panel (right-click the panel ›
Add Widgets…), and remove the stock Application Menu / Global Menu widgets.
Apps already running need a restart before their menus appear.
MSG
