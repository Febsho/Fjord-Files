import QtQuick
import qs.Common

GlassSurface {
    property bool first: false
    property bool last: false

    readonly property real topRadius: first ? FilesMetrics.paneRadius : Theme.groupedListInnerRadius
    readonly property real bottomRadius: last ? FilesMetrics.paneRadius : Theme.groupedListInnerRadius

    anchors.left: parent.left
    anchors.right: parent.right
    baseColor: Theme.foregroundColor(Theme.cardSurface, true)
    edgeLightingEnabled: first || last
    topLeftRadius: topRadius
    topRightRadius: topRadius
    bottomLeftRadius: bottomRadius
    bottomRightRadius: bottomRadius
}
