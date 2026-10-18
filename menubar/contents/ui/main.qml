import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami

// One macOS-style menu bar: the Apple menu, the bold app menu, and the
// focused app's own menus (read from its global menu through the
// vivaldi-menu-bridge helper's MenuProxy). All menus share one popup system,
// so after one click you can sweep across every title, and Left/Right move
// between menus.
PlasmoidItem {
    id: root

    readonly property string helper: Qt.resolvedUrl("../code/helper.py").toString().replace("file://", "")
    readonly property string proxyService: "org.brhett.VivaldiMenu"

    // Focused app; frozen while a menu is open (our popup takes focus).
    property string activeName: ""
    property string activeAppId: ""
    property string menuService: ""
    property string menuPath: ""
    property var appMenu: null       // JSON tree from the proxy
    property int menuSerial: 0       // ignores stale proxy replies

    property string fullName: ""
    property var recentApps: []
    property var recentDocs: []

    property int openIndex: -1       // index into `titles`, -1 when closed

    // The strip: Apple menu, app menu, then the app's own menus.
    readonly property var titles: {
        const list = [{ kind: "apple" }, { kind: "app", label: activeName || i18n("Desktop") }];
        const top = appMenu && appMenu.children ? appMenu.children : [];
        for (const node of top) {
            if (node.visible !== false && node.label) {
                list.push({ kind: "dbus", label: node.label, node: node });
            }
        }
        return list;
    }

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: ""

    // Plasma sizes the applet from its full representation; the strip itself
    // lives at the root (so functions here can reach it) and moves into it.
    fullRepresentation: Item {
        Layout.minimumWidth: strip.implicitWidth
        Layout.preferredWidth: strip.implicitWidth
        Layout.maximumWidth: strip.implicitWidth
        Layout.fillHeight: true
        Component.onCompleted: strip.parent = this
    }

    // ---- helpers ----------------------------------------------------------
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    P5Support.DataSource {
        id: executable
        property var callbacks: ({})
        property int serial: 0
        engine: "executable"
        connectedSources: []

        function exec(cmd, callback) {
            const source = cmd + " #" + (++serial);
            if (callback) {
                callbacks[source] = callback;
            }
            connectSource(source);
        }
        onNewData: (sourceName, data) => {
            const callback = callbacks[sourceName];
            delete callbacks[sourceName];
            disconnectSource(sourceName);
            if (callback) {
                callback(data["stdout"] || "");
            }
        }
    }

    function launch(cmd) {
        executable.exec("setsid -f " + cmd + " >/dev/null 2>&1");
    }

    function dbusSend(service, path, method) {
        launch("dbus-send --session --type=method_call --dest=" + service + " " + path + " " + method);
    }

    function helperJson(command, callback) {
        executable.exec("python3 -I " + shellQuote(helper) + " " + command, out => {
            try {
                callback(JSON.parse(out));
            } catch (e) {
                console.warn("menubar: helper " + command + " failed:", e, JSON.stringify(out));
            }
        });
    }

    function proxy(member, args, signature, callback) {
        const reply = DBus.SessionBus.asyncCall({
            service: proxyService, path: "/MenuProxy", iface: "org.brhett.MenuProxy",
            member: member, arguments: args, signature: signature,
        });
        if (callback) {
            reply.finished.connect(() => {
                let data = null;
                if (!reply.isError) {
                    try {
                        data = JSON.parse(reply.value);
                    } catch (e) {}
                }
                callback(data);
            });
        }
    }

    // ---- focused app --------------------------------------------------------
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: true
        filterByActivity: true
        filterNotMinimized: false
        onActiveTaskChanged: root.updateActive()
    }

    Instantiator {
        model: tasks
        delegate: QtObject {
            required property var model
            readonly property bool active: model.IsActive === true
            readonly property string service: model.ApplicationMenuServiceName || ""
            onActiveChanged: root.updateActive()
            onServiceChanged: if (active) root.updateActive()
        }
    }

    function updateActive() {
        if (openIndex >= 0) {
            return;
        }
        const idx = tasks.activeTask;
        const valid = idx && idx.valid;
        const role = r => valid ? (tasks.data(idx, r) || "") : "";
        const name = valid ? (role(TaskManager.AbstractTasksModel.AppName) || tasks.data(idx, Qt.DisplayRole) || "") : "";
        const service = role(TaskManager.AbstractTasksModel.ApplicationMenuServiceName);
        const path = role(TaskManager.AbstractTasksModel.ApplicationMenuObjectPath);
        const appChanged = service !== menuService || path !== menuPath;
        activeName = name;
        activeAppId = role(TaskManager.AbstractTasksModel.AppId);
        menuService = service;
        menuPath = path;
        if (appChanged) {
            loadAppMenu();
        }
    }

    function loadAppMenu() {
        const serial = ++menuSerial;
        if (!menuService || !menuPath) {
            appMenu = null;
            return;
        }
        proxy("GetMenu", [menuService, menuPath], "(ss)", data => {
            if (serial === root.menuSerial) {
                root.appMenu = data;
            }
        });
    }

    // Menus can change while the app runs; refresh when the app is refocused.
    Timer {
        interval: 4000
        repeat: true
        running: root.menuService !== "" && root.openIndex < 0
        onTriggered: root.loadAppMenu()
    }

    function forEachWindow(fn) {
        for (let i = 0; i < tasks.rowCount(); ++i) {
            const idx = tasks.index(i, 0);
            fn(idx, tasks.data(idx, TaskManager.AbstractTasksModel.AppId) === activeAppId);
        }
    }

    function minimized(idx) {
        return tasks.data(idx, TaskManager.AbstractTasksModel.IsMinimized) === true;
    }

    // ---- menu contents --------------------------------------------------------
    function dbusEntries(node) {
        // Capture the app now: by the time an item runs, the menus have closed
        // and focus may not be back on the app yet.
        const service = menuService;
        const path = menuPath;
        const out = [];
        for (const child of node.children || []) {
            if (child.visible === false) {
                continue;
            }
            if (child.separator) {
                out.push({ separator: true });
                continue;
            }
            const entry = {
                label: child.label,
                enabled: child.enabled !== false,
                shortcut: child.shortcut || "",
                check: child.toggle ? (child.checked ? 1 : 0) : undefined,
            };
            if (child.children) {
                entry.submenu = () => dbusEntries(child);
                entry.node = child;
            } else {
                entry.trigger = () => proxy("Activate", [service, path, child.id], "(ssi)");
            }
            out.push(entry);
        }
        // Hidden items leave their separators behind; like a real menu, drop
        // separators at the ends and collapse runs of them into one.
        const tidy = [];
        for (const e of out) {
            if (e.separator && (tidy.length === 0 || tidy[tidy.length - 1].separator)) {
                continue;
            }
            tidy.push(e);
        }
        while (tidy.length > 0 && tidy[tidy.length - 1].separator) {
            tidy.pop();
        }
        if (tidy.length === 0) {
            tidy.push({ label: i18n("Empty"), enabled: false });
        }
        return tidy;
    }

    // Finds a standard item (about / settings / quit) in the app's own menu.
    function findAppItem(kind) {
        const app = activeName.toLowerCase();
        const notSettings = /shortcut|toolbar|notification|keyboard|spell|language|editor|profile|session|tab/i;
        let best = null;
        let bestScore = 0;
        const walk = node => {
            for (const child of node.children || []) {
                if (child.children) {
                    walk(child);
                    continue;
                }
                if (child.separator || child.enabled === false || child.visible === false) {
                    continue;
                }
                const label = (child.label || "").replace(/[.…]+$/, "").trim().toLowerCase();
                let score = 0;
                if (kind === "about") {
                    if (label.startsWith("about ") && label !== "about kde" && label !== "about qt") {
                        score = label.includes(app) ? 3 : 1;
                    }
                } else if (kind === "settings") {
                    if (label === "settings" || label === "preferences") {
                        score = 3;
                    } else if (label.startsWith("configure ") && !notSettings.test(label)) {
                        score = label.includes(app) ? 3 : 2;
                    } else if (label.endsWith(" settings") && !notSettings.test(label)) {
                        score = 1;
                    }
                } else if (kind === "quit") {
                    if (label === "quit" || label === "exit" || label === "quit " + app || label === "exit " + app) {
                        score = 3;
                    }
                }
                if (score > bestScore) {
                    best = child;
                    bestScore = score;
                }
            }
        };
        if (appMenu) {
            walk(appMenu);
        }
        return best;
    }

    function appEntries() {
        if (!activeName) {
            return [{ label: i18n("Show All"), trigger: showAll }];
        }
        const service = menuService;
        const path = menuPath;
        const activate = node => () => proxy("Activate", [service, path, node.id], "(ssi)");
        const about = findAppItem("about");
        const settings = findAppItem("settings");
        const quit = findAppItem("quit");
        return [
            { label: i18n("About %1", activeName), enabled: !!about, trigger: about ? activate(about) : null },
            { separator: true },
            { label: i18n("Settings…"), enabled: !!settings, trigger: settings ? activate(settings) : null },
            { separator: true },
            { label: i18n("Hide %1", activeName), trigger: () => hideApp(true) },
            { label: i18n("Hide Others"), trigger: () => hideApp(false) },
            { label: i18n("Show All"), trigger: showAll },
            { separator: true },
            { label: i18n("Quit %1", activeName), trigger: quit ? activate(quit) : closeAppWindows },
        ];
    }

    function hideApp(mine) {
        forEachWindow((idx, isApp) => {
            if (isApp === mine && !minimized(idx)) {
                tasks.requestToggleMinimized(idx);
            }
        });
    }

    function showAll() {
        forEachWindow(idx => {
            if (minimized(idx)) {
                tasks.requestToggleMinimized(idx);
            }
        });
    }

    function closeAppWindows() {
        forEachWindow((idx, isApp) => {
            if (isApp) {
                tasks.requestClose(idx);
            }
        });
    }

    function recentEntries() {
        const out = [];
        if (recentApps.length > 0) {
            out.push({ header: true, label: i18n("Applications") });
            for (const a of recentApps) {
                out.push({ label: a.name, trigger: () => launch("kstart --application " + shellQuote(a.id)) });
            }
        }
        if (recentDocs.length > 0) {
            if (out.length > 0) {
                out.push({ separator: true });
            }
            out.push({ header: true, label: i18n("Documents") });
            for (const d of recentDocs) {
                out.push({ label: d.name, trigger: () => launch("xdg-open " + shellQuote(d.path)) });
            }
        }
        if (out.length === 0) {
            out.push({ label: i18n("No Recent Items"), enabled: false });
        }
        out.push({ separator: true });
        out.push({ label: i18n("Clear Menu"), enabled: recentApps.length > 0 || recentDocs.length > 0,
                   trigger: () => helperJson("clear", () => refreshRecent()) });
        return out;
    }

    function appleEntries() {
        const logout = "org.kde.LogoutPrompt";
        return [
            { label: i18n("About This Computer"), trigger: () => aboutWindow.showInfo(root) },
            { separator: true },
            { label: i18n("System Settings…"), trigger: () => launch("systemsettings") },
            { label: i18n("App Store…"), trigger: () => launch("plasma-discover") },
            { separator: true },
            { label: i18n("Recent Items"), submenu: recentEntries },
            { separator: true },
            { label: i18n("Force Quit…"), trigger: () => forceQuitWindow.showRefreshed() },
            { separator: true },
            { label: i18n("Sleep"), trigger: () => launch("systemctl suspend") },
            { label: i18n("Restart…"), trigger: () => dbusSend(logout, "/LogoutPrompt", logout + ".promptReboot") },
            { label: i18n("Shut Down…"), trigger: () => dbusSend(logout, "/LogoutPrompt", logout + ".promptShutDown") },
            { separator: true },
            { label: i18n("Lock Screen"), shortcut: "⌘L",
              trigger: () => dbusSend("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver.Lock") },
            { label: fullName ? i18n("Log Out %1…", fullName) : i18n("Log Out…"), shortcut: "⌃⌥⌦",
              trigger: () => dbusSend(logout, "/LogoutPrompt", logout + ".promptLogout") },
        ];
    }

    function refreshRecent() {
        helperJson("recent", data => {
            recentApps = data.apps;
            recentDocs = data.docs;
        });
    }

    function entriesFor(index) {
        const t = titles[index];
        if (!t) {
            return [];
        }
        if (t.kind === "apple") {
            return appleEntries();
        }
        if (t.kind === "app") {
            return appEntries();
        }
        return dbusEntries(t.node);
    }

    Component.onCompleted: {
        helperJson("user", data => fullName = data.name);
        updateActive();
    }

    // ---- opening and closing ----------------------------------------------------
    // While a menu is open, a transparent overlay covers the screen below the
    // bar: it holds keyboard focus and catches clicks outside the menus. The
    // menus themselves are blurred Plasma dialogs that never take focus, so
    // switching menus can't trip focus-loss handling. The bar stays
    // uncovered, so hovering across titles keeps working.
    property var panels: []          // [{ key, entries, anchor }]; [0] is the open menu
    // One row per open menu window. Rows are only added or removed where the
    // set of open menus actually changes, so opening a submenu or refreshing
    // a menu's items leaves the other windows alone. (An array model would
    // rebuild every window on any change.)
    ListModel {
        id: panelModel
    }

    function setPanels(next) {
        let same = 0;
        while (same < next.length && same < panelModel.count && panelModel.get(same).key === next[same].key) {
            ++same;
        }
        // Data first, so surviving windows read the new entries.
        panels = next;
        while (panelModel.count > same) {
            panelModel.remove(panelModel.count - 1);
        }
        for (let i = same; i < next.length; ++i) {
            panelModel.append({ key: next[i].key });
        }
    }

    function stripWindow() {
        return strip.Window.window;
    }

    function showOverlay() {
        if (overlay.visible) {
            return;
        }
        const win = stripWindow();
        const screen = Plasmoid.containment.screenGeometry;
        overlay.x = screen.x;
        overlay.y = win ? win.y + win.height : screen.y;
        overlay.overlayWidth = screen.width;
        overlay.overlayHeight = screen.y + screen.height - overlay.y;
        overlayFallback.expired = false;
        overlayFallback.restart();
        overlay.visible = true;
        overlay.requestActivate();
        overlayContent.forceActiveFocus();
    }

    function openMenu(index) {
        if (!titles[index]) {
            return;
        }
        openIndex = index;
        showOverlay();
        setPanels([{ key: "menu" + index, entries: entriesFor(index), anchor: titleRepeater.itemAt(index) }]);
        if (titles[index].kind === "apple") {
            refreshRecent();
        } else if (titles[index].kind === "dbus") {
            // Let the app update this menu (e.g. Vivaldi's history) and redraw.
            const node = titles[index].node;
            proxy("Refresh", [menuService, menuPath, node.id], "(ssi)", data => {
                if (data && root.openIndex === index && root.panels.length === 1) {
                    root.setPanels([Object.assign({}, root.panels[0], { entries: root.dbusEntries(data) })]);
                }
            });
        }
    }

    function closeAll() {
        setPanels([]);
        overlay.visible = false;
        openIndex = -1;
        // Focus returns to the app a moment after the overlay hides; check
        // the focused app once it has settled.
        settleTimer.restart();
    }

    Timer {
        id: settleTimer
        interval: 300
        onTriggered: root.updateActive()
    }

    function activate(entry) {
        if (!entry || entry.enabled === false || !entry.trigger) {
            return;
        }
        const trigger = entry.trigger;
        // Closing destroys the row that's calling us, so run the action on
        // the next turn of the event loop rather than from inside it.
        Qt.callLater(() => {
            root.closeAll();
            trigger();
        });
    }

    // MenuView of panel `level`: 0 is the open menu, 1.. are submenus.
    function viewAt(level) {
        const panel = panelWindows.objectAt(level);
        return panel ? panel.mainItem : null;
    }

    // Opens `entry`'s submenu next to `row` (a row in panel `level`).
    function openSubmenu(level, entry, row) {
        closeSubmenus(level);
        if (!entry || !entry.submenu || entry.enabled === false || !row) {
            return;
        }
        const next = panels.slice(0, level + 1);
        next.push({ key: panels[level].key + "/" + viewAt(level).current, entries: entry.submenu(), anchor: row, row: row });
        setPanels(next);
        viewAt(level).openSubmenuIndex = viewAt(level).current;
        if (entry.node) {
            proxy("Refresh", [menuService, menuPath, entry.node.id], "(ssi)", data => {
                const p = root.panels;
                if (data && p.length > level + 1 && p[level + 1].row === row) {
                    const updated = p.slice();
                    updated[level + 1] = Object.assign({}, p[level + 1], { entries: root.dbusEntries(data) });
                    root.setPanels(updated);
                }
            });
        }
    }

    // Closes submenus opened from panel `level` and deeper.
    function closeSubmenus(level) {
        if (panels.length > level + 1) {
            setPanels(panels.slice(0, level + 1));
        }
        const view = viewAt(level);
        if (view) {
            view.openSubmenuIndex = -1;
        }
    }

    function onHovered(level, index, row) {
        const entry = viewAt(level).entries[index];
        if (entry && entry.submenu) {
            if (!(panels.length > level + 1 && panels[level + 1].row === row)) {
                openSubmenu(level, entry, row);
            }
        } else {
            closeSubmenus(level);
        }
    }

    // ---- keyboard ------------------------------------------------------------------
    function handleKey(event) {
        const depth = panels.length - 1;
        const view = viewAt(depth);
        if (!view) {
            return;
        }
        switch (event.key) {
        case Qt.Key_Escape:
            if (depth > 0) {
                closeSubmenus(depth - 1);
            } else {
                closeAll();
            }
            break;
        case Qt.Key_Down:
            view.move(1);
            break;
        case Qt.Key_Up:
            view.move(-1);
            break;
        case Qt.Key_Right: {
            const entry = view.entries[view.current];
            if (entry && entry.submenu) {
                openSubmenu(depth, entry, view.rowAt(view.current));
                const sub = viewAt(depth + 1);
                if (sub) {
                    sub.current = -1;
                    sub.move(1);
                }
            } else {
                openMenu((openIndex + 1) % titles.length);
            }
            break;
        }
        case Qt.Key_Left:
            if (depth > 0) {
                closeSubmenus(depth - 1);
            } else {
                openMenu((openIndex - 1 + titles.length) % titles.length);
            }
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space: {
            const entry = view.entries[view.current];
            if (entry && entry.submenu) {
                openSubmenu(depth, entry, view.rowAt(view.current));
            } else {
                view.choose(view.current);
            }
            break;
        }
        default:
            return;
        }
        event.accepted = true;
    }

    // ---- overlay ----------------------------------------------------------------
    PlasmaCore.Dialog {
        id: overlay

        property int overlayWidth: 0
        property int overlayHeight: 0

        // A normal-layer window: it covers apps (it's the newest) but always
        // stays below the menus, which are in the stay-on-top layer. Being
        // focused would otherwise raise it over them and steal their clicks.
        type: PlasmaCore.Dialog.Normal
        location: PlasmaCore.Types.Floating
        backgroundHints: PlasmaCore.Dialog.NoBackground
        flags: Qt.FramelessWindowHint
        visible: false

        mainItem: Item {
            id: overlayContent
            width: overlay.overlayWidth
            height: overlay.overlayHeight
            focus: true
            Keys.onPressed: event => root.handleKey(event)

            // A click anywhere outside the menus closes them.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.closeAll()
            }
        }
    }

    function showPendingMenus() {
        for (let i = 0; i < panelModel.count; ++i) {
            const dialog = panelWindows.objectAt(i);
            if (dialog && !dialog.visible) {
                placeAndShow(dialog, i);
            }
        }
    }

    Connections {
        target: overlay
        function onActiveChanged() {
            if (overlay.active) {
                root.showPendingMenus();
            }
        }
    }

    // If KWin never focuses the overlay, show the menus anyway after a moment.
    Timer {
        id: overlayFallback
        property bool expired: false
        interval: 250
        onTriggered: {
            expired = true;
            root.showPendingMenus();
        }
    }

    // One blurred popup per open menu level. Keys are stable while a menu is
    // just being refreshed, so the window isn't recreated (no flicker).
    // Placed by hand (Floating): Plasma would centre a popup under its
    // anchor, but a macOS menu starts at its title's left edge and a
    // submenu sits against its parent menu.
    function placeAndShow(dialog, index) {
        const panel = panels[index];
        const anchor = panel ? panel.anchor : null;
        // The anchor can vanish if the title strip was rebuilt meanwhile.
        const win = anchor && anchor.Window ? anchor.Window.window : null;
        if (!dialog || !win || panelWindows.objectAt(index) !== dialog) {
            return;
        }
        // Focusing the overlay raises it, so menus must appear only after it
        // is active or the overlay ends up on top and swallows their clicks.
        // onActiveChanged below (or the fallback timer) shows pending menus.
        if (!overlay.active && !overlayFallback.expired) {
            return;
        }
        const screen = Plasmoid.containment.screenGeometry;
        const pos = anchor.mapToItem(null, 0, 0);
        let x, y;
        if (index === 0) {
            x = win.x + pos.x;
            y = win.y + win.height;
        } else {
            const parentMenu = panelWindows.objectAt(index - 1);
            x = win.x + win.width - 1;
            y = win.y + pos.y - (parentMenu ? parentMenu.margins.top : 0);
            if (x + dialog.width > screen.x + screen.width) {
                x = win.x - dialog.width + 1;   // no room: open to the left
            }
        }
        dialog.x = Math.max(screen.x, Math.min(x, screen.x + screen.width - dialog.width));
        dialog.y = Math.max(screen.y, Math.min(y, screen.y + screen.height - dialog.height));
        dialog.visible = true;
    }

    Instantiator {
        id: panelWindows
        model: panelModel
        delegate: PlasmaCore.Dialog {
            id: panelWindow

            required property int index
            readonly property var panel: root.panels[index]

            type: PlasmaCore.Dialog.PopupMenu
            location: PlasmaCore.Types.Floating
            flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
            visible: false

            // Position before mapping: Wayland won't move a window once shown.
            // (A fresh closure per window: Qt.callLater merges repeated calls
            // to the same function, which would show only the last window.)
            Component.onCompleted: Qt.callLater(() => root.placeAndShow(panelWindow, index))

            mainItem: MenuView {
                level: index
                entries: panel ? panel.entries : []
                onActivated: entry => root.activate(entry)
                onHovered: (i, row) => root.onHovered(level, i, row)
            }
        }
    }

    ForceQuitWindow {
        id: forceQuitWindow
        onForceQuit: pid => executable.exec("kill -9 " + pid)
    }

    AboutWindow {
        id: aboutWindow
        logo: Plasmoid.configuration.icon
        onMoreInfo: root.launch("kinfocenter")
    }

    // ---- the strip ----------------------------------------------------------------
    RowLayout {
        id: strip
        anchors.fill: parent
        spacing: 0

        Repeater {
            id: titleRepeater
            model: root.titles

            delegate: MouseArea {
                id: title

                required property int index
                required property var modelData
                readonly property bool isApple: modelData.kind === "apple"
                readonly property bool isOpen: root.openIndex === index

                Layout.fillHeight: true
                implicitWidth: (isApple ? Plasmoid.configuration.iconSize : label.implicitWidth) + Kirigami.Units.largeSpacing * 2
                hoverEnabled: true

                onPressed: {
                    if (isOpen) {
                        root.closeAll();
                    } else {
                        root.openMenu(index);
                    }
                }
                // Sweeping across titles while a menu is open switches menus.
                onContainsMouseChanged: {
                    if (containsMouse && root.openIndex >= 0 && !isOpen) {
                        root.openMenu(index);
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: Kirigami.Units.smallSpacing / 2
                    anchors.bottomMargin: Kirigami.Units.smallSpacing / 2
                    radius: 4
                    color: Kirigami.Theme.textColor
                    opacity: title.isOpen ? 0.18 : (title.containsMouse ? 0.08 : 0)
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Plasmoid.configuration.iconSize
                    height: width
                    visible: title.isApple
                    source: Plasmoid.configuration.icon
                    isMask: Plasmoid.configuration.monochrome
                    color: Kirigami.Theme.textColor
                    roundToIconSize: false
                }

                PlasmaComponents3.Label {
                    id: label
                    anchors.centerIn: parent
                    visible: !title.isApple
                    text: title.modelData.label || ""
                    font.weight: title.modelData.kind === "app" ? Font.Bold : Font.Normal
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
