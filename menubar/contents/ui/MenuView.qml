import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The contents of one open menu or submenu. `entries` is a list of plain
// objects: { label, enabled, separator, header, shortcut, check, submenu,
// trigger }. `submenu` is a function returning entries; `trigger` runs the
// item. Keyboard navigation is driven by the menu bar through `current`.
Item {
    id: view

    property var entries: []
    property int current: -1
    property int level: 0
    property int openSubmenuIndex: -1
    readonly property bool hasChecks: entries.some(e => e && e.check !== undefined && e.check >= 0)

    signal activated(var entry)
    signal hovered(int index, Item row)

    // macOS confirms a choice by blinking the item's highlight off and on
    // once before the menu closes; `activated` follows the blink.
    property int flashIndex: -1
    property bool flashOn: true

    function choose(index) {
        if (blink.running || !selectable(index)) {
            return;
        }
        flashIndex = index;
        blink.start();
    }

    SequentialAnimation {
        id: blink
        ScriptAction { script: view.flashOn = false }
        PauseAnimation { duration: 70 }
        ScriptAction { script: view.flashOn = true }
        PauseAnimation { duration: 70 }
        ScriptAction {
            script: {
                const entry = view.entries[view.flashIndex];
                view.flashIndex = -1;
                view.activated(entry);
            }
        }
    }

    function rowAt(index) {
        return repeater.itemAt(index);
    }

    function selectable(index) {
        const e = entries[index];
        return e && !e.separator && !e.header && e.enabled !== false;
    }

    // Moves the keyboard highlight by `step`, skipping separators and
    // disabled rows.
    function move(step) {
        if (entries.length === 0) {
            return;
        }
        let i = current;
        for (let n = 0; n < entries.length; ++n) {
            i = (i + step + entries.length) % entries.length;
            if (i < 0) {
                i = entries.length - 1;
            }
            if (selectable(i)) {
                current = i;
                return;
            }
        }
    }

    implicitWidth: Math.max(column.implicitWidth, Kirigami.Units.gridUnit * 14)
    implicitHeight: column.implicitHeight
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        id: column
        width: view.width
        spacing: 0

        Repeater {
            id: repeater
            model: view.entries

            delegate: Loader {
                id: rowLoader

                required property var modelData
                required property int index

                Layout.fillWidth: true
                sourceComponent: modelData.separator ? separatorComponent
                               : modelData.header ? headerComponent
                               : itemComponent

                Component {
                    id: separatorComponent
                    MacMenuSeparator {}
                }
                Component {
                    id: headerComponent
                    MacMenuHeader {
                        text: rowLoader.modelData.label
                    }
                }
                Component {
                    id: itemComponent
                    MacMenuItem {
                        text: rowLoader.modelData.label
                        shortcut: rowLoader.modelData.shortcut || ""
                        enabled: rowLoader.modelData.enabled !== false
                        hasSubmenu: !!rowLoader.modelData.submenu
                        submenuOpen: view.openSubmenuIndex === rowLoader.index
                        current: view.current === rowLoader.index
                        flashing: view.flashIndex === rowLoader.index
                        flashOn: view.flashOn
                        checkState: view.hasChecks ? (rowLoader.modelData.check === 1 ? 1 : 0) : -1
                        onContainsMouseChanged: {
                            if (containsMouse) {
                                view.current = rowLoader.index;
                                view.hovered(rowLoader.index, rowLoader);
                            }
                        }
                        // This replaces MacMenuItem's own onClicked, so it must
                        // handle both cases itself.
                        onClicked: {
                            if (rowLoader.modelData.submenu) {
                                view.hovered(rowLoader.index, rowLoader);
                            } else {
                                view.choose(rowLoader.index);
                            }
                        }
                    }
                }
            }
        }
    }
}
