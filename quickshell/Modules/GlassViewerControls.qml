import QtQuick
import QtQuick.Layouts
import qs.Common

Item {
    id: root

    default property alias contentData: controls.data
    property Item refractionSource: null
    property bool refractionLive: true
    property var refractionRevision: 0
    property alias spacing: controls.spacing

    implicitWidth: controls.implicitWidth
    implicitHeight: controls.implicitHeight

    GlassSurface {
        anchors.fill: parent
        z: -1
        baseColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.floatingWindowForegroundAlpha * (root.refractionSource !== null ? 0.54 : 0.84))
        topLeftRadius: Theme.cornerRadiusL
        topRightRadius: Theme.cornerRadiusL
        bottomLeftRadius: Theme.cornerRadiusL
        bottomRightRadius: Theme.cornerRadiusL
        refractionSource: root.refractionSource
        refractionLive: root.refractionLive
        refractionRevision: root.refractionRevision
    }

    RowLayout {
        id: controls

        anchors.fill: parent
    }
}
