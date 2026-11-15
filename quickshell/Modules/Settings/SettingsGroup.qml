import QtQuick
import qs.Common

Item {
    id: root

    default property alias content: rows.data
    readonly property bool isSettingsGroup: true

    width: parent?.width ?? 0
    implicitHeight: rows.implicitHeight
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusM
        color: SettingsMetrics.rowColor
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.12)
    }

    Column {
        id: rows
        width: parent.width
        spacing: 0
    }
}
