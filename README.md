# kde-mac-menubar

A macOS-style menu bar for KDE Plasma 6: the Apple menu, the bold app-name menu
and the focused app's own menus (File, Edit, View…) in one strip, with one
popup system so you can sweep across menus like on a Mac.

- **Apple menu**: About This Computer, System Settings…, App Store…, Recent
  Items, Force Quit…, Sleep, Restart…, Shut Down…, Lock Screen, Log Out….
- **App menu**: About, Settings…, Hide, Hide Others, Show All, Quit, read
  from the app's own menu where it has them.
- **Global menu**: the focused app's menus, exported over `dbusmenu` (KDE and
  Qt apps, and GTK apps with `appmenu-gtk-module`).
- Mac touches: hover-sweep between open menus, the selection blink on click,
  rounded blue-highlight menus.
- **Vivaldi** (optional): real Mac-style File/Edit/View/History/Bookmarks/
  Window/Help menus for Vivaldi, with checkmarks that follow Vivaldi's state,
  through a small browser extension.

## Install

```sh
./install.sh             # widget + menu helper
./install.sh --vivaldi   # ...and the Vivaldi menus
```

Then right-click your top panel › **Add Widgets…** › **Menu Bar**, and remove
the stock *Application Menu* / *Global Menu* widgets. Apps that were already
running need a restart before their menus show.

Needs Plasma 6 and Python 3 with PyGObject (`python3-gobject` on Fedora,
`python3-gi` on Debian/Ubuntu). `ydotool` is optional (a few Vivaldi
commands are typed as keystrokes).

## How it fits together

- `menubar/` is the Plasma widget (`org.brhett.menubar`).
- `bridge/vivaldi-menu-bridge` is a user service the widget relies on even
  without Vivaldi: it owns `com.canonical.AppMenu.Registrar` (which Plasma
  only provides while its stock menu widget is on a panel, so apps would stop
  exporting menus otherwise) and serves apps' menus to the widget as JSON
  over D-Bus (`org.brhett.VivaldiMenu`, `/MenuProxy`).
- `bridge/extension/` plus `bridge/install-vivaldi.sh` add Vivaldi: the
  extension carries out menu commands, and the widget recognises Vivaldi's
  window by its app id, so Vivaldi runs natively on Wayland (with real
  touchpad momentum). The launcher also turns off Vivaldi's laggy smooth
  scrolling. (Only the stock Global Menu widget would need Vivaldi on
  XWayland: `install-vivaldi.sh --x11` sets that up, and the helper then
  tags Vivaldi's X11 windows for it.) `hide-menu-button.css` is an optional
  Vivaldi CSS mod that hides its own menu button.

## Uninstall

Remove the widget from your panel, then `./uninstall.sh`.

## License

GPL-2.0-or-later. See [LICENSE](LICENSE).
