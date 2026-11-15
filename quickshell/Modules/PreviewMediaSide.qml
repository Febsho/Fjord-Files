pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common

Rectangle {
    id: root
    property url source: ""
    property bool video: false
    readonly property alias player: preview.player
    signal expandRequested()
    color: Theme.surfaceContainer
    radius: Theme.cornerRadiusL
    clip: true

    PreviewMedia {
        id: preview
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        anchors.topMargin: expand.height + Theme.spacingS
        source: root.source
        video: root.video
        autoPlay: root.video
        audioOutput.muted: root.video
        compact: true
    }
    Label {
        anchors.centerIn: preview
        width: preview.width
        visible: preview.errorMessage !== ""
        text: preview.errorMessage
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }
    ToolButton {
        id: expand
        anchors.top: parent.top
        anchors.right: parent.right
        text: "⤢"
        Accessible.name: I18n.tr("Open full preview", "sidebar media preview")
        onClicked: root.expandRequested()
    }
}
