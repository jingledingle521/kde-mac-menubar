import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Gray, non-interactive section title ("Applications", "Documents").
PlasmaComponents3.Label {
    Layout.fillWidth: true
    leftPadding: Kirigami.Units.mediumSpacing
    topPadding: Kirigami.Units.smallSpacing / 2
    bottomPadding: Kirigami.Units.smallSpacing / 2
    font.weight: Font.DemiBold
    opacity: 0.5
}
