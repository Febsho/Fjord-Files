pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.DCommon.FileBrowser

Item {
    id: root

    property string path: ""
    property var previewReader: (filePath, callback) => DuxFilesService.call("files.officePreview", {"path": filePath}, callback)
    readonly property var pdfView: pdf.item
    readonly property string errorMessage: preview.errorMessage || (pdf.item?.failed
        ? I18n.tr("This file could not be opened", "large preview placeholder") : "")

    OfficePreviewSource { id: preview; path: root.path; previewReader: root.previewReader }

    Loader {
        id: pdf
        anchors.fill: parent
        active: preview.pdfPath !== ""
        source: active ? "PreviewPdf.qml" : ""
        onLoaded: item.source = Qt.binding(() => FilePaths.toFileUrl(preview.pdfPath))
    }

    Label {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacingL * 2, 420)
        visible: preview.pdfPath === ""
        text: preview.errorMessage || I18n.tr("Preparing preview…", "Office document preview")
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }
}
