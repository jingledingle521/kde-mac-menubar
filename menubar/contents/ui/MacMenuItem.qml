import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// One row of the menu: label, optional icon, right-aligned shortcut or
// submenu arrow, and the macOS rounded accent highlight on hover.
MouseArea {
    id: item

    property alias text: label.text
    property string shortcut: ""
    property var iconSource: ""
    property bool hasSubmenu: false
    property bool submenuOpen: false
    // Highlighted by keyboard navigation.
    property bool current: false
    // -1: no checkmark column, 0: unchecked (space kept), 1: checked.
    property int checkState: -1
    // While the chosen item blinks (macOS selection feedback), the blink
    // alone decides the highlight.
    property bool flashing: false
    property bool flashOn: true
    readonly property bool highlighted: enabled && (flashing ? flashOn : (containsMouse || submenuOpen || current))
    readonly property color foreground: highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor

    signal triggered()

    Layout.fillWidth: true
    implicitWidth: row.implicitWidth + 2 * Kirigami.Units.mediumSpacing
    implicitHeight: Math.round(label.implicitHeight + Kirigami.Units.smallSpacing * 1.5)
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4

    onClicked: if (!hasSubmenu) triggered()

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: Kirigami.Theme.highlightColor
        visible: item.highlighted
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.mediumSpacing
        anchors.rightMargin: Kirigami.Units.mediumSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: "checkmark"
            color: item.foreground
            isMask: true
            visible: item.checkState >= 0
            opacity: item.checkState === 1 ? 1 : 0
        }
        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: item.iconSource
            visible: item.iconSource !== ""
        }
        PlasmaComponents3.Label {
            id: label
            Layout.fillWidth: true
            color: item.foreground
            elide: Text.ElideRight
        }
        PlasmaComponents3.Label {
            Layout.leftMargin: Kirigami.Units.gridUnit
            text: item.shortcut
            visible: text.length > 0
            color: item.foreground
            opacity: item.highlighted ? 1 : 0.45
        }
        Kirigami.Icon {
            Layout.leftMargin: Kirigami.Units.gridUnit
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: "go-next-symbolic"
            color: item.foreground
            isMask: true
            visible: item.hasSubmenu
        }
    }
}
