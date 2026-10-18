import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// macOS "About This Mac" layout: logo, model name, spec rows, More Info.
Window {
    id: win

    property string logo: ""
    property var info: ({})

    signal moreInfo()

    function showInfo(menu) {
        menu.helperJson("info", data => info = data);
        show();
        raise();
        requestActivate();
    }

    title: i18n("About This Computer")
    flags: Qt.Dialog
    readonly property int fixedWidth: Kirigami.Units.gridUnit * 19
    readonly property int fixedHeight: column.implicitHeight + Kirigami.Units.gridUnit * 3

    width: fixedWidth
    height: fixedHeight
    minimumWidth: fixedWidth
    maximumWidth: fixedWidth
    minimumHeight: fixedHeight
    maximumHeight: fixedHeight
    color: Kirigami.Theme.backgroundColor

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    Shortcut {
        sequence: "Escape"
        onActivated: win.close()
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.gridUnit * 1.5
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            Layout.preferredHeight: Kirigami.Units.gridUnit * 7
            Layout.bottomMargin: Kirigami.Units.largeSpacing
            source: win.logo
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: win.info.model || ""
            font.pixelSize: Kirigami.Units.gridUnit * 1.4
            font.weight: Font.Bold
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.gridUnit
            horizontalAlignment: Text.AlignHCenter
            text: win.info.vendor || ""
            opacity: 0.6
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            Repeater {
                model: [
                    [i18n("Chip"), win.info.cpu],
                    [i18n("Graphics"), (win.info.gpu || []).join("\n")],
                    [i18n("Memory"), win.info.memory],
                    [i18n("Computer name"), win.info.hostname],
                    [i18n("OS"), win.info.os],
                    [i18n("Kernel"), win.info.kernel]
                ].filter(row => row[1])
                delegate: Item {
                    required property var modelData
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    implicitHeight: Math.max(key.implicitHeight, value.implicitHeight)

                    PlasmaComponents3.Label {
                        id: key
                        anchors.right: parent.horizontalCenter
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        text: modelData[0]
                        font.weight: Font.DemiBold
                    }
                    PlasmaComponents3.Label {
                        id: value
                        anchors.left: parent.horizontalCenter
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        width: column.width / 2 - Kirigami.Units.smallSpacing
                        text: modelData[1]
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                    }
                }
            }
        }

        PlasmaComponents3.Button {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.gridUnit
            text: i18n("More Info…")
            onClicked: {
                win.close();
                win.moreInfo();
            }
        }
    }
}
