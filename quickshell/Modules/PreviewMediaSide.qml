pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.DCommon.FileBrowser

Rectangle {
    id: root
    property url source: ""
    property url thumbnailSource: ""
    property url generatedThumbnail: ""
    property string thumbnailRequestSource: ""
    readonly property url posterSource: thumbnailSource.toString() !== "" ? thumbnailSource : generatedThumbnail
    property bool video: false
    property var videoChoices: []
    property string currentPath: ""
    property bool canStepPrevious: false
    property bool canStepNext: false
    readonly property alias player: preview.player
    signal expandRequested()
    signal fullScreenRequested()
    signal clipStepRequested(int direction)
    signal clipSelected(string path)
    color: "transparent"
    radius: 0
    clip: true

    onSourceChanged: {
        generatedThumbnail = "";
        thumbnailRequestSource = "";
        requestThumbnail();
    }
    onThumbnailSourceChanged: if (thumbnailSource.toString() === "") requestThumbnail()
    onVideoChanged: requestThumbnail()

    function requestThumbnail() {
        if (!video || thumbnailSource.toString() !== "" || source.toString() === "" || thumbnailRequestSource === source.toString())
            return;
        const requestedSource = source.toString();
        thumbnailRequestSource = requestedSource;
        const path = FilePaths.fromUrl(source);
        DirectoryService.thumbnails([path], "large", "", result => {
            if (root.source.toString() !== requestedSource || result.error)
                return;
            const thumbnail = result.results?.find(item => item.path === path)?.thumbnail ?? "";
            if (thumbnail !== "")
                root.generatedThumbnail = FilePaths.toFileUrl(thumbnail);
        });
    }

    PreviewMedia {
        id: preview
        anchors.fill: parent
        source: root.source
        posterSource: root.posterSource
        video: root.video
        autoPlay: false
        startMuted: root.video
        compact: true
        onFullScreenRequested: root.fullScreenRequested()
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
    ComboBox {
        anchors.left: parent.left
        anchors.right: expand.left
        anchors.rightMargin: Theme.spacingS
        anchors.top: parent.top
        visible: root.video && root.videoChoices.length > 1
        model: root.videoChoices.map(entry => entry.name)
        currentIndex: Math.max(0, root.videoChoices.findIndex(entry => entry.path === root.currentPath))
        Accessible.name: I18n.tr("Choose video", "video preview navigation")
        onActivated: index => root.clipSelected(root.videoChoices[index]?.path ?? "")
    }
    ToolButton {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "‹"
        visible: root.video && root.canStepPrevious
        Accessible.name: I18n.tr("Previous video", "video preview navigation")
        onClicked: root.clipStepRequested(-1)
    }
    ToolButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        visible: root.video && root.canStepNext
        Accessible.name: I18n.tr("Next video", "video preview navigation")
        onClicked: root.clipStepRequested(1)
    }
}
