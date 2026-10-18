import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.iconthemes as KIconThemes

KCM.SimpleKCM {
    property string cfg_icon
    property alias cfg_iconSize: sizeSpin.value
    property alias cfg_monochrome: monoCheck.checked

    Kirigami.FormLayout {
        QQC2.Button {
            id: iconButton

            Kirigami.FormData.label: i18n("Icon:")
            implicitWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.largeSpacing * 2
            implicitHeight: implicitWidth
            onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.open()

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Choose an icon from your icon theme or an image file")

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                source: cfg_icon
                isMask: monoCheck.checked
                color: Kirigami.Theme.textColor
            }

            QQC2.Menu {
                id: iconMenu
                y: iconButton.height

                QQC2.MenuItem {
                    text: i18n("Choose…")
                    icon.name: "document-open-folder"
                    onClicked: iconDialog.open()
                }
                QQC2.MenuItem {
                    text: i18n("Reset to Fedora Logo")
                    icon.name: "edit-reset"
                    onClicked: cfg_icon = "fedora-logo-icon"
                }
            }
        }

        KIconThemes.IconDialog {
            id: iconDialog
            onIconNameChanged: if (iconName) cfg_icon = iconName
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Icon size:")

            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                from: 8
                to: 64
                stepSize: 1
                value: sizeSpin.value
                onMoved: sizeSpin.value = value
            }
            QQC2.SpinBox {
                id: sizeSpin
                from: 8
                to: 64
                textFromValue: (value, locale) => i18n("%1 px", value)
                valueFromText: (text, locale) => parseInt(text)
            }
        }

        QQC2.CheckBox {
            id: monoCheck
            Kirigami.FormData.label: i18n("Style:")
            text: i18n("Monochrome (tint to the panel text color, like macOS)")
        }
    }
}
