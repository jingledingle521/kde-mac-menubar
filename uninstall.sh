#!/usr/bin/env bash
# Remove the Menu Bar widget and its helper. Remove the widget from your
# panel first (or Plasma shows a "widget missing" placeholder).
set -euo pipefail

config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}

systemctl --user disable --now vivaldi-menu-bridge.service 2>/dev/null || true
rm -f "$config/systemd/user/vivaldi-menu-bridge.service" "$HOME/.local/bin/vivaldi-menu-bridge"
systemctl --user daemon-reload
kpackagetool6 -t Plasma/Applet --remove org.brhett.menubar 2>/dev/null || true
rm -rf "$data/mac-menu-bridge" "$HOME/snap/vivaldi/common/mac-menu-bridge"
echo "Removed. Vivaldi launcher overrides (if installed) are in $data/applications/; delete vivaldi*.desktop there to undo them."
