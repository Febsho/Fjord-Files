import QtQuick
import qs.Common
import qs.DCommon.Widgets

DActionButton {
    focusPolicy: Qt.TabFocus
    buttonSize: FilesMetrics.topbarControlSize
    iconSize: Theme.iconSizeMedium
    iconColor: Theme.surfaceText
    backgroundColor: hovered ? Theme.withAlpha(Theme.glassTint, Theme.stateLayerHover) : "transparent"
}
