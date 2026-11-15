pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Pdf
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property url source: ""
    property real zoom: 1
    property real angle: 0
    property real fitScale: 1
    property bool fitWidth: false
    property bool showThumbnails: false
    property bool showMetadata: false
    readonly property string documentTitle: ready ? document.title : ""
    readonly property string documentAuthor: ready ? document.author : ""
    readonly property string documentSubject: ready ? document.subject : ""
    readonly property int status: document.status
    readonly property bool ready: document.status === PdfDocument.Ready
    readonly property bool failed: document.status === PdfDocument.Error
    readonly property int pageCount: document.pageCount
    readonly property int currentPage: view.currentPage
    readonly property int searchCount: view.searchModel.count
    property alias searchText: search.text

    function goToPage(page) {
        if (ready && page >= 0 && page < pageCount)
            view.goToPage(page);
    }

    function searchStep(direction) {
        const count = view.searchModel.count;
        if (!count)
            return;
        const current = view.searchModel.currentResult;
        view.searchModel.currentResult = current < 0 ? (direction > 0 ? 0 : count - 1)
            : (current + direction + count) % count;
    }

    function applyView() {
        if (!ready || view.width < 2 || view.height < 2)
            return;
        view.pageRotation = angle;
        if (fitWidth)
            view.scaleToWidth(view.width, view.height);
        else
            view.scaleToPage(view.width, view.height);
        fitScale = view.renderScale;
        view.renderScale = fitScale * zoom;
    }

    onZoomChanged: applyView()
    onAngleChanged: applyView()
    onFitWidthChanged: applyView()
    onSourceChanged: {
        search.text = "";
        showThumbnails = false;
        showMetadata = false;
    }

    PdfDocument { id: document; source: root.source }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            visible: root.ready
            spacing: 4
            ToolButton { text: "☰"; Accessible.name: I18n.tr("Toggle page thumbnails", "PDF preview"); checkable: true; checked: root.showThumbnails; onClicked: root.showThumbnails = checked }
            ToolButton { objectName: "pdfMetadataToggle"; text: "ⓘ"; Accessible.name: I18n.tr("Document information", "PDF preview"); checkable: true; checked: root.showMetadata; onClicked: root.showMetadata = checked }
            ToolButton { text: "‹"; Accessible.name: I18n.tr("Previous page", "PDF preview"); enabled: root.currentPage > 0; onClicked: root.goToPage(root.currentPage - 1) }
            SpinBox {
                id: pageNumber
                objectName: "pdfPageNumber"
                from: 1
                to: Math.max(1, root.pageCount)
                editable: true
                value: Math.max(1, root.currentPage + 1)
                onValueModified: root.goToPage(value - 1)
            }
            Label { text: "/ " + root.pageCount; color: Theme.surfaceVariantText }
            ToolButton { text: "›"; Accessible.name: I18n.tr("Next page", "PDF preview"); enabled: root.currentPage >= 0 && root.currentPage + 1 < root.pageCount; onClicked: root.goToPage(root.currentPage + 1) }
            ToolButton { text: root.fitWidth ? I18n.tr("Fit width", "PDF preview") : I18n.tr("Fit page", "PDF preview"); onClicked: root.fitWidth = !root.fitWidth }
            Item { Layout.fillWidth: true }
            TextField {
                id: search
                objectName: "pdfSearch"
                Layout.preferredWidth: 150
                Layout.minimumWidth: 70
                placeholderText: I18n.tr("Find in PDF", "PDF preview")
                selectByMouse: true
                onAccepted: root.searchStep(1)
            }
            Label { text: search.text ? (root.searchCount ? (view.searchModel.currentResult + 1) + "/" + root.searchCount : "0/0") : ""; color: Theme.surfaceVariantText }
            ToolButton { text: "↑"; Accessible.name: I18n.tr("Previous result", "PDF preview"); enabled: root.searchCount > 0; onClicked: root.searchStep(-1) }
            ToolButton { text: "↓"; Accessible.name: I18n.tr("Next result", "PDF preview"); enabled: root.searchCount > 0; onClicked: root.searchStep(1) }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            DListView {
                id: thumbnails
                objectName: "pdfThumbnails"
                visible: root.ready && root.showThumbnails
                Layout.preferredWidth: 120
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.ready ? root.pageCount : 0
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    id: thumbnail
                    required property int index
                    width: thumbnails.width
                    height: 145
                    highlighted: index === root.currentPage
                    Accessible.name: I18n.tr("Page", "PDF preview") + " " + (index + 1)
                    onClicked: root.goToPage(index)
                    contentItem: Column {
                        spacing: 2
                        PdfPageImage {
                            document: document
                            currentFrame: thumbnail.index
                            width: 94
                            height: 115
                            sourceSize.width: 188
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Label { width: 94; horizontalAlignment: Text.AlignHCenter; text: thumbnail.index + 1 }
                    }
                }
            }
            ScrollView {
                objectName: "pdfMetadata"
                visible: root.ready && root.showMetadata
                Layout.preferredWidth: 210
                Layout.maximumWidth: Math.max(100, root.width * 0.4)
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: parent.width
                    Repeater {
                        model: [
                            {"label": I18n.tr("Title", "PDF metadata"), "value": document.title},
                            {"label": I18n.tr("Author", "PDF metadata"), "value": document.author},
                            {"label": I18n.tr("Subject", "PDF metadata"), "value": document.subject},
                            {"label": I18n.tr("Keywords", "PDF metadata"), "value": document.keywords},
                            {"label": I18n.tr("Creator", "PDF metadata"), "value": document.creator},
                            {"label": I18n.tr("Producer", "PDF metadata"), "value": document.producer}
                        ]
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            visible: modelData.value !== ""
                            Label { text: modelData.label; font.bold: true; color: Theme.surfaceText }
                            Label { Layout.fillWidth: true; text: modelData.value; wrapMode: Text.Wrap; color: Theme.surfaceVariantText; textFormat: Text.PlainText }
                        }
                    }
                    Label { text: I18n.tr("Pages", "PDF metadata") + ": " + root.pageCount; color: Theme.surfaceText }
                }
            }
            PdfMultiPageView {
                id: view
                objectName: "pdfPages"
                Layout.fillWidth: true
                Layout.fillHeight: true
                document: document
                searchString: search.text
                focus: false
                activeFocusOnTab: false
                onWidthChanged: root.applyView()
                onHeightChanged: root.applyView()
            }
        }
    }
    Connections { target: document; function onStatusChanged() { root.applyView(); } }
}
