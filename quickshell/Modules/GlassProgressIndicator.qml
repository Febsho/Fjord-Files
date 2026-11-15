import QtQuick
import QtQuick.Controls
import qs.Common

ProgressBar {
    id: root

    implicitHeight: Theme.spacingXS

    background: Rectangle {
        implicitHeight: Theme.spacingXS
        radius: height / 2
        color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.76)
    }

    contentItem: Item {
        implicitHeight: Theme.spacingXS
        clip: true

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: height / 2
            color: Theme.glassTint
        }
    }
}
