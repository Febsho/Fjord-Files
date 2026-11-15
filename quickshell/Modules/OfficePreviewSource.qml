pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

Item {
    id: root

    width: 0
    height: 0
    visible: false

    property string path: ""
    property string pdfPath: ""
    property string errorMessage: ""
    property bool loading: false
    property int requestId: 0
    property var previewReader: (filePath, callback) => DuxFilesService.call("files.officePreview", {"path": filePath}, callback)

    function request() {
        const serial = ++requestId;
        pdfPath = "";
        errorMessage = "";
        loading = false;
        if (path === "")
            return;
        if (!PdfService.available) {
            errorMessage = PdfService.unavailable
                ? I18n.tr("PDF preview is not available. Install %1 support to view this file.", "large preview warning when an optional module is missing, %1 is Qt PDF").arg("Qt PDF")
                : I18n.tr("Loading…", "PDF preview");
            return;
        }
        loading = true;
        previewReader(path, result => {
            if (serial !== requestId)
                return;
            loading = false;
            if (result.error) {
                errorMessage = result.error;
                return;
            }
            pdfPath = result.path ?? "";
            if (pdfPath === "")
                errorMessage = I18n.tr("This file could not be opened", "large preview placeholder");
        });
    }

    onPathChanged: request()

    Component.onCompleted: {
        PdfService.ensureProbed();
        request();
    }

    Connections {
        target: PdfService
        function onAvailableChanged() { root.request(); }
        function onUnavailableChanged() { if (PdfService.unavailable) root.request(); }
    }
}
