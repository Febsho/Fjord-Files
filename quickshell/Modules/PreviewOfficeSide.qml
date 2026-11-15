pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Pdf
import qs.Common
import qs.DCommon.FileBrowser

Rectangle {
    id: root
    property string path: ""
    signal expandRequested()
    color: Theme.surfaceContainer
    radius: Theme.cornerRadiusL
    clip: true

    OfficePreviewSource { id: preview; path: root.path }
    PdfDocument { id: document; source: preview.pdfPath !== "" ? FilePaths.toFileUrl(preview.pdfPath) : "" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: document.title || I18n.tr("Office preview", "sidebar Office preview")
                elide: Text.ElideMiddle
                color: Theme.surfaceText
            }
            ToolButton {
                text: "⤢"
                Accessible.name: I18n.tr("Open full preview", "sidebar PDF preview")
                onClicked: root.expandRequested()
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            PdfPageImage {
                anchors.fill: parent
                visible: document.status === PdfDocument.Ready
                document: document
                currentFrame: 0
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Label {
                anchors.centerIn: parent
                width: parent.width
                visible: document.status !== PdfDocument.Ready
                text: preview.errorMessage || (document.status === PdfDocument.Error
                    ? I18n.tr("This file could not be opened", "PDF preview") : I18n.tr("Loading…", "PDF preview"))
                color: Theme.surfaceVariantText
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
