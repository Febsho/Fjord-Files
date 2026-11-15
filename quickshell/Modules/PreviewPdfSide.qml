pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Pdf
import qs.Common

Rectangle {
    id: root
    property url source: ""
    readonly property bool ready: document.status === PdfDocument.Ready
    readonly property bool failed: document.status === PdfDocument.Error
    readonly property int pageCount: document.pageCount
    property int currentPage: 0
    signal expandRequested()
    color: Theme.surfaceContainer
    radius: Theme.cornerRadiusL
    clip: true
    onSourceChanged: currentPage = 0

    PdfDocument { id: document; source: root.source }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: document.title || I18n.tr("PDF preview", "sidebar PDF preview")
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
                visible: root.ready
                document: document
                currentFrame: root.currentPage
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Label {
                anchors.centerIn: parent
                visible: !root.ready
                text: root.failed ? I18n.tr("This file could not be opened", "PDF preview") : I18n.tr("Loading…", "PDF preview")
                color: Theme.surfaceVariantText
                wrapMode: Text.Wrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.ready
            ToolButton {
                text: "‹"
                Accessible.name: I18n.tr("Previous page", "PDF preview")
                enabled: root.currentPage > 0
                onClicked: root.currentPage--
            }
            Label { text: (root.currentPage + 1) + " / " + root.pageCount; color: Theme.surfaceText }
            ToolButton {
                text: "›"
                Accessible.name: I18n.tr("Next page", "PDF preview")
                enabled: root.currentPage + 1 < root.pageCount
                onClicked: root.currentPage++
            }
        }
    }
}
