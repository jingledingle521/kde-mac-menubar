import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

// "Force Quit Applications": one row per running app (by process), then
// SIGKILL after a confirmation, like macOS.
Window {
    id: win

    signal forceQuit(int pid)

    property var apps: []
    property int selected: -1
    property bool confirming: false

    function refresh() {
        const seen = {};
        const result = [];
        for (let i = 0; i < tasks.count; ++i) {
            const idx = tasks.makeModelIndex(i);
            const pid = tasks.data(idx, TaskManager.AbstractTasksModel.AppPid);
            // plasmashell owns this window; killing it takes down the desktop.
            const isShell = tasks.data(idx, TaskManager.AbstractTasksModel.AppId) === "org.kde.plasmashell.desktop";
            if (!pid || seen[pid] || isShell) {
                continue;
            }
            seen[pid] = true;
            result.push({
                pid: pid,
                name: tasks.data(idx, TaskManager.AbstractTasksModel.AppName) || tasks.data(idx, Qt.DisplayRole),
                icon: tasks.data(idx, Qt.DecorationRole)
            });
        }
        result.sort((a, b) => a.name.localeCompare(b.name));
        const keep = selected >= 0 && selected < apps.length ? apps[selected].pid : -1;
        apps = result;
        selected = result.findIndex(a => a.pid === keep);
    }

    function showRefreshed() {
        confirming = false;
        refresh();
        show();
        raise();
        requestActivate();
    }

    title: i18n("Force Quit Applications")
    flags: Qt.Dialog
    width: Kirigami.Units.gridUnit * 22
    height: Kirigami.Units.gridUnit * 24
    minimumWidth: Kirigami.Units.gridUnit * 18
    minimumHeight: Kirigami.Units.gridUnit * 16
    color: Kirigami.Theme.backgroundColor

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false
        filterNotMinimized: false
        onCountChanged: if (win.visible) win.refresh()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: win.confirming ? win.confirming = false : win.close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 2
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("If an app doesn't respond for a while, select its name and click Force Quit.")
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Kirigami.Theme.alternateBackgroundColor
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            radius: 6
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 4
                model: win.apps
                currentIndex: win.selected
                boundsBehavior: Flickable.StopAtBounds

                delegate: MouseArea {
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
                    onClicked: win.selected = index
                    onDoubleClicked: {
                        win.selected = index;
                        win.confirming = true;
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Kirigami.Theme.highlightColor
                        visible: index === win.selected
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                        spacing: Kirigami.Units.largeSpacing
                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            source: modelData.icon
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: index === win.selected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        }
                    }
                }
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: win.confirming
            wrapMode: Text.WordWrap
            font.weight: Font.DemiBold
            text: win.selected >= 0 ? i18n("Do you want to force “%1” to quit? You will lose any unsaved changes.", win.apps[win.selected].name) : ""
        }

        RowLayout {
            Layout.fillWidth: true
            Item {
                Layout.fillWidth: true
            }
            PlasmaComponents3.Button {
                text: i18n("Cancel")
                visible: win.confirming
                onClicked: win.confirming = false
            }
            PlasmaComponents3.Button {
                text: i18n("Force Quit")
                enabled: win.selected >= 0
                onClicked: {
                    if (!win.confirming) {
                        win.confirming = true;
                        return;
                    }
                    win.forceQuit(win.apps[win.selected].pid);
                    win.confirming = false;
                    win.selected = -1;
                }
            }
        }
    }
}
