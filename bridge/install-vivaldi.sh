#!/usr/bin/env bash
# Mac-style File/Edit/View/History/Bookmarks/Window/Help for Vivaldi in KDE's
# global menu: the helper publishes the menu and attaches it to Vivaldi's
# windows, and the Mac Menu Bridge extension carries out the commands.
# The Menu Bar widget finds Vivaldi by its app id, so Vivaldi runs natively on
# Wayland (with real touchpad momentum). The launcher override adds
# --ozone-platform=wayland and turns off Vivaldi's smooth-scrolling animation.
# With --x11 Vivaldi runs through XWayland instead, which the stock Global
# Menu widget needs (the helper tags its X11 windows with the menu).
set -euo pipefail

platform=wayland
[ "${1:-}" = --x11 ] && platform=x11

here=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
# Snap Vivaldi can only read its own folder, not hidden paths in your home.
if [ -d "$HOME/snap/vivaldi" ]; then
    ext="$HOME/snap/vivaldi/common/mac-menu-bridge"
else
    ext="$data/mac-menu-bridge"
fi

mkdir -p "$HOME/.local/bin" "$config/systemd/user" "$data/applications"
install -m 755 "$here/vivaldi-menu-bridge" "$HOME/.local/bin/vivaldi-menu-bridge"
cp "$here/vivaldi-menu-bridge.service" "$config/systemd/user/"

# Launcher override: same entry, plus the platform and no smooth scrolling on every Exec line.
for src in /var/lib/snapd/desktop/applications/vivaldi_vivaldi-stable.desktop \
           /usr/share/applications/vivaldi-stable.desktop; do
    if [ -f "$src" ]; then
        sed -E 's#^(Exec=[^ ]+( '"'"'--class=[^'"'"']*'"'"')?)#\1 --ozone-platform='"$platform"' --disable-smooth-scrolling#' "$src" \
            > "$data/applications/$(basename "$src")"
    fi
done
update-desktop-database "$data/applications" 2>/dev/null || true

rm -rf "$ext"
mkdir -p "$ext"
cp "$here/extension/manifest.json" "$here/extension/background.js" "$ext/"
"$HOME/.local/bin/vivaldi-menu-bridge" --config | python3 -I -c '
import json, sys
cfg = json.load(sys.stdin)
print("self.BRIDGE = %s;" % json.dumps({"port": cfg["port"], "token": cfg["token"]}))' > "$ext/config.js"
chmod 600 "$ext/config.js"

# Shortcuts for Vivaldi commands the menu needs (toggle tab/address bar,
# panels, images, toolbar editor). Vivaldi must be closed for this.
"$HOME/.local/bin/vivaldi-menu-bridge" --bind-vivaldi || \
    echo "  Quit Vivaldi and run: ~/.local/bin/vivaldi-menu-bridge --bind-vivaldi"

systemctl --user daemon-reload
systemctl --user enable --now vivaldi-menu-bridge.service
systemctl --user restart vivaldi-menu-bridge.service

cat <<MSG

Installed. Two one-time steps:
 1. In Vivaldi open vivaldi://extensions, turn on "Developer mode",
    click "Load unpacked" and choose:
      $ext
 2. Quit Vivaldi completely and start it again. Its menus then appear in
    the Menu Bar widget.
MSG
