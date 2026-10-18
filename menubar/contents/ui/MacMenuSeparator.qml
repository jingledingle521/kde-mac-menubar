import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    Layout.fillWidth: true
    implicitHeight: Kirigami.Units.smallSpacing * 2 + 1

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Kirigami.Units.mediumSpacing
        anchors.rightMargin: Kirigami.Units.mediumSpacing
        height: 1
        color: Kirigami.Theme.textColor
        opacity: 0.15
    }
}
