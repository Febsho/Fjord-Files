pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.FileBrowser
import "../Common/PreviewView.js" as PreviewView
import "../Common/SyntaxHighlight.js" as SyntaxHighlight

FocusScope {
    id: overlay

    property var entry: null
    property bool open: false
    property bool embedded: false
    property bool shortcutsActive: true
    property bool textSearchOpen: false
    property bool textWrap: true
    property bool textLineNumbers: false
    property bool textEditMode: false
    property real zoom: 1
    property real angle: 0
    property real panX: 0
    property real panY: 0
    property bool mirrored: false
    property int imageWidth: 0
    property int imageHeight: 0
    property bool cropSelecting: false
    property real cropStartX: 0
    property real cropStartY: 0
    property real cropCurrentX: 0
    property real cropCurrentY: 0
    property var imageCrop: null
    property bool imageExporting: false
    property int imageExportRequest: 0
    property var archiveEntries: []
    property string archiveFolder: ""
    property string archiveSelection: ""
    property string archiveSearch: ""
    onArchiveSearchChanged: archiveSelection = ""
    onArchiveFolderChanged: archiveSelection = ""
    property string archiveError: ""
    property bool archiveLoading: false
    property bool archiveTruncated: false
    property int archiveRequest: 0
    property var archiveReader: (filePath, callback) => DuxFilesService.call("files.archiveList", {"path": filePath}, callback)
    readonly property var archiveChildren: {
        const query = archiveSearch.trim().toLocaleLowerCase();
        if (query !== "") {
            return archiveEntries.filter(entry => entry.path.toLocaleLowerCase().includes(query))
                .map(entry => ({"name": entry.path, "path": entry.path.replace(/\/$/, ""), "dir": entry.dir, "size": entry.size}))
                .sort((a, b) => a.name.localeCompare(b.name));
        }
        const prefix = archiveFolder === "" ? "" : archiveFolder + "/";
        const found = {};
        for (const entry of archiveEntries) {
            if (!entry.path.startsWith(prefix)) continue;
            const rest = entry.path.substring(prefix.length);
            if (!rest) continue;
            const slash = rest.indexOf("/");
            const name = slash < 0 ? rest : rest.substring(0, slash);
            if (!found[name] || slash >= 0 || entry.dir)
                found[name] = {"name": name, "path": prefix + name, "dir": slash >= 0 || entry.dir, "size": entry.size};
        }
        return Object.values(found).sort((a, b) => (a.dir === b.dir ? a.name.localeCompare(b.name) : (a.dir ? -1 : 1)));
    }
    property string textContent: ""
    property string textError: ""
    property string textReadOnlyReason: ""
    property bool textTruncated: false
    property bool textLoading: false
    property bool textSaving: false
    property string textRevision: ""
    property string textSaved: ""
    property bool textExternalChanged: false
    property bool textRevisionCheckPending: false
    property int textRevisionRequest: 0
    readonly property string syntaxLanguage: SyntaxHighlight.languageFor(path)
    readonly property string syntaxMarkup: textEditMode || textSearchOpen ? "" : SyntaxHighlight.highlight(textContent, syntaxLanguage, {
        "keyword": Theme.primary,
        "number": Theme.tertiary,
        "string": Theme.secondary,
        "comment": Theme.surfaceText
    })
    readonly property bool textDirty: kind === "text" && textRevision !== "" && textContent !== textSaved
    property var pendingLeave: null
    property var textWriter: (filePath, revision, text, callback) => DuxFilesService.call("files.textSave", {"path": filePath, "revision": revision, "text": text}, callback)
    property var textRevisionReader: (filePath, callback) => DuxFilesService.call("files.textRevision", {"path": filePath}, callback)
    property int textRequest: 0
    readonly property bool rummageImageHelper: !!Quickshell.env("FJORD_RUMMAGE_PREVIEW_V4")
    property int imageRequest: 0
    property string isolatedImage: ""
    property string imageError: ""
    property var imageReader: rummageImageHelper
        ? (filePath, callback) => DuxFilesService.call("files.rummagePreview", {"path": filePath, "maxWidth": 1024, "maxHeight": 1024}, callback)
        : (filePath, callback) => DuxFilesService.call("files.imagePreview", {"path": filePath, "maxWidth": 1024, "maxHeight": 1024}, callback)
    property var imageExportWriter: (params, callback) => DuxFilesService.call("files.imageExport", params, callback)
    property var textReader: (filePath, limit, callback) => DuxFilesService.call("files.textRead", {"path": filePath}, callback)
    property var textFallbackReader: (filePath, limit, callback) => DirectoryService.preview(filePath, limit, callback)
    property var officePreviewReader: (filePath, callback) => DuxFilesService.call("files.officePreview", {"path": filePath}, callback)

    readonly property string path: entry?.path ?? ""
    readonly property string kind: open && entry ? (entry.viewer || PreviewView.kindFor(entry.mime)) : ""
    readonly property string imageDetails: {
        if (kind !== "image")
            return "";
        const parts = [];
        if (imageWidth > 0 && imageHeight > 0)
            parts.push(imageWidth + " × " + imageHeight);
        if (entry?.size >= 0)
            parts.push(FileFormat.size(entry.size));
        return parts.join(" · ");
    }
    readonly property bool turned: PreviewView.normalizeAngle(angle) % 180 !== 0
    readonly property real devicePixelRatio: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio
    readonly property int rasterBucket: Math.min(8, Math.max(1, Math.ceil(zoom)))
    readonly property real originalZoom: picture.paintedWidth > 0 && imageWidth > 0 ? imageWidth / picture.paintedWidth : 0
    readonly property alias imageStage: stage
    readonly property alias pageView: pages.item
    readonly property alias mediaView: media.item
    readonly property alias officeView: office.item
    readonly property string errorMessage: {
        if (kind === "text")
            return textError;
        if (kind === "archive")
            return archiveError;
        if (kind === "media" && media.status === Loader.Error)
            return I18n.tr("Media preview is not available. Install Qt Multimedia support to view this file.", "preview warning when Qt Multimedia is missing");
        if (kind === "media" && mediaView?.errorMessage)
            return mediaView.errorMessage;
        if (kind === "image" && imageError !== "")
            return imageError;
        if (kind === "pdf" && PdfService.unavailable)
            return I18n.tr("PDF preview is not available. Install %1 support to view this file.", "large preview warning when an optional module is missing, %1 is Qt PDF").arg("Qt PDF");
        if (kind === "office" && office.status === Loader.Error)
            return I18n.tr("This file could not be opened", "large preview placeholder");
        if (kind === "office" && officeView?.errorMessage)
            return officeView.errorMessage;
        if ((kind === "image" && picture.status === Image.Error) || (kind === "pdf" && (pages.status === Loader.Error || pageView?.failed)))
            return I18n.tr("This file could not be opened", "large preview placeholder");
        return "";
    }

    signal archiveExtractRequested(string archive, string member)
    signal galleryStepRequested(int direction)
    signal closed
    signal savedAs(var entry)

    visible: open
    opacity: open ? 1 : 0
    z: 2
    focus: open

    Behavior on opacity {
        enabled: Theme.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
        }
    }

    function present(target) {
        if (!supports(target))
            return;
        if (open && (textDirty || textSaving)) {
            confirmLeave(() => present(target));
            return;
        }
        textRequest++;
        imageRequest++;
        imageExportRequest++;
        imageExporting = false;
        textSearchOpen = false;
        textEditMode = false;
        isolatedImage = "";
        imageError = "";
        imageWidth = 0;
        imageHeight = 0;
        cropSelecting = false;
        imageCrop = null;
        entry = target;
        reset();
        open = true;
        if (kind === "pdf")
            PdfService.ensureProbed();
        if (kind === "text")
            loadText();
        if (kind === "archive")
            loadArchive();
        if (kind === "image")
            loadImage();
        forceActiveFocus();
    }

    function supports(target) {
        return (target?.viewer || PreviewView.kindFor(target?.mime ?? "")) !== "";
    }

    function loadImage() {
        const request = imageRequest;
        imageReader(path, result => {
            if (request !== overlay.imageRequest || !overlay.open)
                return;
            if (result.error) {
                overlay.imageError = result.error;
                return;
            }
            overlay.imageWidth = result.fullWidth ?? result.width ?? 0;
            overlay.imageHeight = result.fullHeight ?? result.height ?? 0;
            overlay.isolatedImage = result.url ?? "";
        });
    }

    function loadArchive() {
        const request = ++archiveRequest;
        archiveEntries = [];
        archiveFolder = "";
        archiveSearch = "";
        archiveSelection = "";
        archiveError = "";
        archiveTruncated = false;
        archiveLoading = true;
        archiveReader(path, result => {
            if (request !== overlay.archiveRequest || !overlay.open) return;
            overlay.archiveLoading = false;
            if (result.error) { overlay.archiveError = result.error; return; }
            overlay.archiveEntries = result.entries ?? [];
            overlay.archiveTruncated = result.truncated === true;
        });
    }

    function loadText() {
        const request = ++textRequest;
        textRevisionRequest++;
        textRevisionCheckPending = false;
        textContent = "";
        textSaved = "";
        textRevision = "";
        textExternalChanged = false;
        textError = "";
        textReadOnlyReason = "";
        textTruncated = false;
        textLoading = true;
        textReader(path, 262144, result => {
            if (request !== overlay.textRequest || !overlay.open)
                return;
            overlay.textLoading = false;
            if (result.error) {
                if (result.error.includes("file is too large to edit") || result.error.includes("file is not supported UTF-8 text")) {
                    overlay.textLoading = true;
                    overlay.textReadOnlyReason = I18n.tr("This file is available in read-only preview.", "text preview cannot be edited safely");
                    overlay.textFallbackReader(overlay.path, 262144, fallback => {
                        if (request !== overlay.textRequest || !overlay.open) return;
                        overlay.textLoading = false;
                        if (fallback.error) { overlay.textError = fallback.error; return; }
                        if (fallback.binary) { overlay.textError = I18n.tr("Binary file", "preview column note for files without readable text"); return; }
                        overlay.textContent = fallback.text ?? "";
                        overlay.textTruncated = fallback.truncated === true;
                    });
                    return;
                }
                overlay.textError = result.error;
                return;
            }
            if (result.binary) {
                overlay.textError = I18n.tr("Binary file", "preview column note for files without readable text");
                return;
            }
            overlay.textContent = result.text ?? "";
            overlay.textSaved = overlay.textContent;
            overlay.textRevision = result.revision ?? "";
            overlay.textTruncated = result.truncated === true;
        });
    }

    function checkTextRevision() {
        if (!open || kind !== "text" || textRevision === "" || textExternalChanged || textRevisionCheckPending)
            return;
        const request = ++textRevisionRequest;
        const targetPath = path;
        const expectedRevision = textRevision;
        textRevisionCheckPending = true;
        textRevisionReader(targetPath, result => {
            if (request !== overlay.textRevisionRequest)
                return;
            overlay.textRevisionCheckPending = false;
            if (!overlay.open || overlay.path !== targetPath)
                return;
            if (result.error || result.revision !== expectedRevision)
                overlay.textExternalChanged = true;
        });
    }

    function confirmLeave(action) {
        if (textSaving)
            return;
        if (!textDirty) {
            action();
            return;
        }
        pendingLeave = action;
        discardDialog.open();
    }

    function saveText() {
        if (!textDirty || textSaving || !textRevision)
            return;
        const saved = textContent;
        textSaving = true;
        textError = "";
        textWriter(path, textRevision, saved, result => {
            overlay.textSaving = false;
            if (result.error) {
                overlay.textError = result.error;
                if (result.error.includes("changed on disk"))
                    overlay.textExternalChanged = true;
                return;
            }
            overlay.textRevision = result.revision;
            overlay.textSaved = saved;
            if (result.path) {
                const name = result.path.substring(result.path.lastIndexOf("/") + 1);
                overlay.entry = Object.assign({}, overlay.entry, {"path": result.path, "name": name});
                overlay.savedAs(overlay.entry);
            }
        });
    }

    function dismiss(notify = true) {
        if (!open)
            return;
        if (textDirty || textSaving) {
            confirmLeave(() => dismiss(notify));
            return;
        }
        open = false;
        textRequest++;
        textRevisionRequest++;
        textRevisionCheckPending = false;
        imageRequest++;
        imageExportRequest++;
        imageExporting = false;
        archiveRequest++;
        archiveEntries = [];
        isolatedImage = "";
        imageError = "";
        textContent = "";
        textError = "";
        textLoading = false;
        textSearchOpen = false;
        entry = null;
        if (notify)
            closed();
    }

    function reset() {
        zoom = 1;
        angle = 0;
        mirrored = false;
        panX = 0;
        panY = 0;
    }

    function panLimitX() {
        return PreviewView.panLimit(stage.width, stage.height, zoom, angle, picture.paintedWidth || stage.width, picture.paintedHeight || stage.height);
    }

    function panLimitY() {
        return PreviewView.panLimit(stage.height, stage.width, zoom, angle, picture.paintedHeight || stage.height, picture.paintedWidth || stage.width);
    }

    function panTo(x, y) {
        panX = PreviewView.clampPan(x, panLimitX());
        panY = PreviewView.clampPan(y, panLimitY());
    }

    function zoomAt(nextZoom, x, y) {
        const previous = zoom;
        zoom = nextZoom;
        const ratio = zoom / previous;
        panTo(x - stage.width / 2 - (x - stage.width / 2 - panX) * ratio,
              y - stage.height / 2 - (y - stage.height / 2 - panY) * ratio);
    }

    function zoomBy(direction, x = stage.width / 2, y = stage.height / 2) {
        zoomAt(PreviewView.steppedZoom(zoom, direction), x, y);
    }

    function fitImage() {
        zoom = 1;
        panTo(0, 0);
    }

    function beginCrop() {
        if (cropSelecting) {
            cropSelecting = false;
            imageCrop = null;
            return;
        }
        zoom = 1;
        angle = 0;
        mirrored = false;
        panX = 0;
        panY = 0;
        imageCrop = null;
        cropSelecting = true;
    }

    function finishCrop(x, y) {
        cropCurrentX = x;
        cropCurrentY = y;
        const first = picture.mapFromItem(stage, cropStartX, cropStartY);
        const last = picture.mapFromItem(stage, x, y);
        const imageLeft = (picture.width - picture.paintedWidth) / 2;
        const imageTop = (picture.height - picture.paintedHeight) / 2;
        if (picture.paintedWidth <= 0 || picture.paintedHeight <= 0 || imageWidth <= 0 || imageHeight <= 0) {
            cropSelecting = false;
            return;
        }
        const minX = Math.max(imageLeft, Math.min(first.x, last.x));
        const minY = Math.max(imageTop, Math.min(first.y, last.y));
        const maxX = Math.min(imageLeft + picture.paintedWidth, Math.max(first.x, last.x));
        const maxY = Math.min(imageTop + picture.paintedHeight, Math.max(first.y, last.y));
        const x1 = Math.floor((minX - imageLeft) / picture.paintedWidth * imageWidth);
        const y1 = Math.floor((minY - imageTop) / picture.paintedHeight * imageHeight);
        const x2 = Math.ceil((maxX - imageLeft) / picture.paintedWidth * imageWidth);
        const y2 = Math.ceil((maxY - imageTop) / picture.paintedHeight * imageHeight);
        const cropX = Math.max(0, Math.min(imageWidth - 1, x1));
        const cropY = Math.max(0, Math.min(imageHeight - 1, y1));
        const cropRight = Math.max(cropX + 1, Math.min(imageWidth, x2));
        const cropBottom = Math.max(cropY + 1, Math.min(imageHeight, y2));
        imageCrop = {"x": cropX, "y": cropY, "width": cropRight - cropX, "height": cropBottom - cropY};
        cropSelecting = false;
    }

    function exportImage() {
        if (kind !== "image" || imageExporting || imageWidth <= 0 || imageHeight <= 0)
            return;
        const fileName = entry?.name ?? "Image";
        const extension = fileName.lastIndexOf(".");
        const base = extension > 0 ? fileName.substring(0, extension) : fileName;
        imageExportDialogLoader.asynchronous = false;
        imageExportDialogLoader.item.ask(base + "-edited.png");
    }

    function writeImage(name) {
        const fileName = name.trim();
        if (fileName === "" || fileName.includes("/") || fileName.includes("\\") || fileName === "." || fileName === "..") {
            ToastService.info(I18n.tr("Enter a file name without a folder path", "image export name validation"));
            return;
        }
        const outputName = fileName.toLocaleLowerCase().endsWith(".png") ? fileName : fileName + ".png";
        const parent = path.substring(0, path.lastIndexOf("/"));
        const crop = imageCrop ?? {"x": 0, "y": 0, "width": imageWidth, "height": imageHeight};
        const request = ++imageExportRequest;
        imageExporting = true;
        imageExportWriter({
            "path": path,
            "destination": parent + "/" + outputName,
            "x": crop.x,
            "y": crop.y,
            "width": crop.width,
            "height": crop.height,
            "angle": PreviewView.normalizeAngle(angle),
            "mirror": mirrored
        }, result => {
            if (request !== overlay.imageExportRequest)
                return;
            overlay.imageExporting = false;
            if (result.error) {
                ToastService.info(result.error);
                return;
            }
            ToastService.info(I18n.tr("Image exported", "toast after exporting a transformed image"));
        });
    }

    function showOriginalSize() {
        if (originalZoom > 0)
            zoomAt(originalZoom, stage.width / 2, stage.height / 2);
    }

    function rotateBy(step) {
        angle = PreviewView.normalizeAngle(angle + step);
        panTo(panX, panY);
    }

    Keys.onPressed: event => {
        if (kind === "text" && event.key !== Qt.Key_Escape)
            return;
        switch (event.key) {
        case Qt.Key_Escape:
            dismiss();
            break;
        case Qt.Key_Space:
            if (embedded)
                return;
            dismiss();
            break;
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            zoomBy(1);
            break;
        case Qt.Key_Minus:
            zoomBy(-1);
            break;
        case Qt.Key_0:
            reset();
            break;
        case Qt.Key_R:
            rotateBy(event.modifiers & Qt.ShiftModifier ? -90 : 90);
            break;
        case Qt.Key_Left:
            panTo(panX + 48, panY);
            break;
        case Qt.Key_Right:
            panTo(panX - 48, panY);
            break;
        case Qt.Key_Up:
            panTo(panX, panY + 48);
            break;
        case Qt.Key_Down:
            panTo(panX, panY - 48);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrimColor
        visible: !overlay.embedded
        opacity: 0.7
    }

    MouseArea {
        anchors.fill: parent
        enabled: !overlay.embedded
        onClicked: overlay.dismiss()
    }

    Rectangle {
        id: card

        anchors.fill: parent
        anchors.margins: overlay.embedded ? 0 : Theme.spacingXL
        radius: Theme.cornerRadiusL
        color: Theme.foregroundColor(Theme.surfaceContainer, true)
        border.width: Theme.outlineWidth
        border.color: Theme.outlineVariant

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            height: Theme.buttonHeightS

            StyledText {
                anchors.left: parent.left
                anchors.right: overlay.kind === "text" ? textLineNumbersButton.left : overlay.kind === "image" ? galleryPrevious.left : closeButton.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: (overlay.entry?.name ?? "") + (overlay.kind === "text" ? " — " + I18n.tr("Saving creates a new file", "text editor save behavior") : overlay.imageDetails !== "" ? " — " + overlay.imageDetails : "")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideMiddle
            }

            DActionButton {
                id: galleryPrevious
                objectName: "galleryPrevious"
                anchors.right: galleryNext.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "image"
                iconName: "chevron_left"
                tooltipText: I18n.tr("Previous image", "image gallery navigation")
                onClicked: overlay.galleryStepRequested(-1)
            }
            DActionButton {
                id: galleryNext
                objectName: "galleryNext"
                anchors.right: imageExportButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "image"
                iconName: "chevron_right"
                tooltipText: I18n.tr("Next image", "image gallery navigation")
                onClicked: overlay.galleryStepRequested(1)
            }

            DActionButton {
                id: imageExportButton
                objectName: "imageExportButton"
                anchors.right: closeButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "image"
                enabled: !overlay.imageExporting && overlay.imageWidth > 0
                iconName: "save"
                tooltipText: I18n.tr("Export image", "image viewer export action")
                onClicked: overlay.exportImage()
            }

            DActionButton {
                id: textWrapButton
                objectName: "textWrapButton"
                anchors.right: textSearchButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "text"
                iconName: "wrap_text"
                tooltipText: overlay.textWrap ? I18n.tr("Disable word wrap", "text viewer") : I18n.tr("Enable word wrap", "text viewer")
                onClicked: overlay.textWrap = !overlay.textWrap
            }

            DActionButton {
                id: textLineNumbersButton
                objectName: "textLineNumbersButton"
                anchors.right: textWrapButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "text"
                enabled: !overlay.textWrap
                iconName: "format_list_numbered"
                tooltipText: overlay.textLineNumbers ? I18n.tr("Hide line numbers", "text viewer") : I18n.tr("Show line numbers", "text viewer")
                onClicked: overlay.textLineNumbers = !overlay.textLineNumbers
            }

            DActionButton {
                id: textSearchButton
                anchors.right: saveButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "text"
                iconName: "search"
                tooltipText: I18n.tr("Find", "text viewer search")
                onClicked: {
                    overlay.textSearchOpen = !overlay.textSearchOpen;
                    if (overlay.textSearchOpen)
                        textSearch.focusSearch();
                }
            }

            DActionButton {
                id: saveButton
                anchors.right: textEditButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "text"
                enabled: overlay.textDirty && !overlay.textSaving
                iconName: "save"
                tooltipText: I18n.tr("Save as a new file", "save edited text as a new file, keeping the original")
                onClicked: overlay.saveText()
            }

            DActionButton {
                id: textEditButton
                objectName: "textEditButton"
                anchors.right: closeButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.kind === "text" && overlay.textRevision !== "" && !overlay.textTruncated
                iconName: overlay.textEditMode ? "visibility" : "edit"
                tooltipText: overlay.textEditMode ? I18n.tr("View text", "leave text edit mode") : I18n.tr("Edit text", "enter text edit mode")
                onClicked: overlay.textEditMode = !overlay.textEditMode
            }

            DActionButton {
                id: closeButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                tooltipText: I18n.tr("Close", "tooltip on the button closing the large preview")
                onClicked: overlay.dismiss()
            }
        }

        TextSearchBar {
            id: textSearch
            objectName: "previewTextSearch"
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            visible: overlay.kind === "text" && overlay.textSearchOpen
            editor: textBody
            onSelectionFound: Qt.callLater(() => {
                const y = textBody.y + textBody.cursorRectangle.y;
                textScroller.contentY = Math.max(0, Math.min(textScroller.contentHeight - textScroller.height, y - textScroller.height / 2));
            })
            onCloseRequested: {
                overlay.textSearchOpen = false;
                textBody.forceActiveFocus();
            }
        }

        Item {
            id: stage

            anchors.top: textSearch.visible ? textSearch.bottom : header.bottom
            anchors.bottom: controls.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            clip: true

            Item {
                x: overlay.panX
                y: overlay.panY
                width: parent.width
                height: parent.height

            Image {
                id: picture

                anchors.fill: parent
                anchors.margins: Theme.spacingS
                source: visible && overlay.path !== "" ? overlay.isolatedImage : ""
                sourceSize.width: Math.max(1, Math.ceil(width * overlay.devicePixelRatio * overlay.rasterBucket))
                sourceSize.height: Math.max(1, Math.ceil(height * overlay.devicePixelRatio * overlay.rasterBucket))
                visible: overlay.kind === "image"
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                smooth: true
                mirror: overlay.mirrored
                autoTransform: true
                scale: overlay.zoom
                rotation: overlay.angle

            }
            }

            Loader {
                id: pages

                anchors.fill: parent
                active: overlay.kind === "pdf" && PdfService.available
                source: active ? "PreviewPdf.qml" : ""
                onLoaded: {
                    item.source = Qt.binding(() => FilePaths.toFileUrl(overlay.path));
                    item.zoom = Qt.binding(() => overlay.zoom);
                    item.angle = Qt.binding(() => overlay.angle);
                }
            }

            Loader {
                id: media

                anchors.fill: parent
                active: overlay.kind === "media"
                source: active ? "PreviewMedia.qml" : ""
                onLoaded: {
                    item.source = Qt.binding(() => FilePaths.toFileUrl(overlay.path));
                    item.video = Qt.binding(() => (overlay.entry?.mime ?? "").startsWith("video/"));
                }
            }

            Loader {
                id: office
                anchors.fill: parent
                active: overlay.kind === "office"
                source: active ? "PreviewOffice.qml" : ""
                onLoaded: {
                    item.previewReader = Qt.binding(() => overlay.officePreviewReader);
                    item.path = Qt.binding(() => overlay.path);
                }
            }

            ColumnLayout {
                anchors.fill: parent
                visible: overlay.kind === "archive" && overlay.errorMessage === ""
                RowLayout {
                    Layout.fillWidth: true
                    DActionButton {
                        iconName: "arrow_back"
                        enabled: overlay.archiveFolder !== ""
                        tooltipText: I18n.tr("Back", "archive folder navigation")
                        onClicked: overlay.archiveFolder = overlay.archiveFolder.includes("/") ? overlay.archiveFolder.substring(0, overlay.archiveFolder.lastIndexOf("/")) : ""
                    }
                    DActionButton {
                        iconName: "download"
                        enabled: overlay.archiveSelection !== "" && !overlay.archiveLoading
                        tooltipText: I18n.tr("Extract selected file beside the archive without overwriting", "archive extraction")
                        onClicked: overlay.archiveExtractRequested(overlay.path, overlay.archiveSelection)
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "/" + overlay.archiveFolder
                        color: Theme.surfaceText
                        elide: Text.ElideMiddle
                    }
                }
                DTextField {
                    objectName: "archiveSearch"
                    Layout.fillWidth: true
                    placeholderText: I18n.tr("Search archive paths", "archive preview search")
                    text: overlay.archiveSearch
                    onTextEdited: overlay.archiveSearch = text
                }
                StyledText {
                    visible: overlay.archiveLoading || overlay.archiveTruncated
                    text: overlay.archiveLoading ? I18n.tr("Loading…", "loading indicator") : I18n.tr("Archive listing is incomplete", "archive preview limit notice")
                    color: Theme.surfaceVariantText
                }
                DListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: overlay.archiveChildren
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: Theme.buttonHeightS
                        color: hover.containsMouse || overlay.archiveSelection === modelData.path ? Theme.surfaceContainerHigh : "transparent"
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: (parent.modelData.dir ? "📁  " : "📄  ") + parent.modelData.name + (parent.modelData.dir ? "/" : "  (" + parent.modelData.size + " B)")
                            color: Theme.surfaceText
                            elide: Text.ElideMiddle
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: if (!parent.modelData.dir) overlay.archiveSelection = parent.modelData.path
                            onDoubleClicked: if (parent.modelData.dir) {
                                const folder = parent.modelData.path;
                                overlay.archiveSearch = "";
                                overlay.archiveFolder = folder;
                            }
                        }
                    }
                }
            }

            Flickable {
                id: textScroller
                objectName: "textScroller"

                anchors.fill: parent
                visible: overlay.kind === "text" && (overlay.errorMessage === "" || overlay.textRevision !== "")
                clip: true
                contentWidth: Math.max(width, textBody.width + textBody.x + Theme.spacingM)
                contentHeight: textBody.implicitHeight + Theme.spacingM * 2
                boundsBehavior: Flickable.StopAtBounds
                function revealCursor(force) {
                    if (!textBody.activeFocus && force !== true)
                        return;
                    const rect = textBody.cursorRectangle;
                    const left = textBody.x + rect.x;
                    const top = textBody.y + rect.y;
                    if (left < contentX) contentX = left;
                    else if (left + rect.width > contentX + width) contentX = left + rect.width - width + Theme.spacingM;
                    if (top < contentY) contentY = top;
                    else if (top + rect.height > contentY + height) contentY = top + rect.height - height + Theme.spacingM;
                    contentX = Math.max(0, Math.min(contentX, Math.max(0, contentWidth - width)));
                    contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)));
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: overlay.textWrap ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }

                Text {
                    id: textGutter
                    objectName: "textLineNumberGutter"
                    x: Theme.spacingM
                    y: Theme.spacingM
                    width: implicitWidth + Theme.spacingS
                    visible: overlay.kind === "text" && overlay.textLineNumbers && !overlay.textWrap
                    text: Array.from({length: Math.max(1, textBody.text.split("\n").length)}, (_, index) => String(index + 1)).join("\n")
                    color: Theme.surfaceText
                    opacity: 0.55
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignTop
                    font.family: Theme.defaultMonoFontFamily
                    font.pixelSize: Theme.fontSizeMedium
                }

                Text {
                    id: textPreview
                    objectName: "textSyntaxPreview"
                    x: textBody.x
                    y: textBody.y
                    width: overlay.textWrap ? textBody.width : undefined
                    visible: overlay.kind === "text" && !overlay.textEditMode && !overlay.textSearchOpen
                    textFormat: Text.RichText
                    text: overlay.syntaxMarkup
                    color: Theme.surfaceText
                    wrapMode: overlay.textWrap ? Text.Wrap : Text.NoWrap
                    font.family: Theme.defaultMonoFontFamily
                    font.pixelSize: Theme.fontSizeMedium
                }

                TextEdit {
                    id: textBody
                    objectName: "textEditor"
                    visible: overlay.textEditMode || overlay.textSearchOpen
                    onCursorRectangleChanged: textScroller.revealCursor()
                    onActiveFocusChanged: if (activeFocus) textScroller.revealCursor()

                    x: Theme.spacingM + (textGutter.visible ? textGutter.width + Theme.spacingS : 0)
                    y: Theme.spacingM
                    width: overlay.textWrap ? Math.max(0, textScroller.width - x - Theme.spacingM) : undefined
                    readOnly: !overlay.textEditMode || overlay.textLoading || overlay.textSaving || overlay.textRevision === "" || overlay.textTruncated
                    selectByMouse: true
                    persistentSelection: true
                    textFormat: TextEdit.PlainText
                    wrapMode: overlay.textWrap ? TextEdit.Wrap : TextEdit.NoWrap
                    color: Theme.surfaceText
                    font.family: Theme.defaultMonoFontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    text: overlay.textContent
                    onTextChanged: if (!readOnly && text !== overlay.textContent) overlay.textContent = text
                }
            }

            MouseArea {
                id: pans

                anchors.fill: parent
                enabled: overlay.kind === "image" && !overlay.cropSelecting && (overlay.zoom > 1 || overlay.turned)
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                acceptedButtons: Qt.LeftButton

                property real originX: 0
                property real originY: 0
                property real startX: 0
                property real startY: 0

                onPressed: mouse => {
                    originX = mouse.x;
                    originY = mouse.y;
                    startX = overlay.panX;
                    startY = overlay.panY;
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    overlay.panTo(startX + mouse.x - originX, startY + mouse.y - originY);
                }
            }

            MouseArea {
                id: cropSelector
                anchors.fill: parent
                enabled: overlay.kind === "image" && overlay.cropSelecting
                z: 2
                cursorShape: Qt.CrossCursor
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => {
                    overlay.cropStartX = mouse.x;
                    overlay.cropStartY = mouse.y;
                    overlay.cropCurrentX = mouse.x;
                    overlay.cropCurrentY = mouse.y;
                }
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    overlay.cropCurrentX = mouse.x;
                    overlay.cropCurrentY = mouse.y;
                }
                onReleased: mouse => overlay.finishCrop(mouse.x, mouse.y)

                Rectangle {
                    x: Math.min(overlay.cropStartX, overlay.cropCurrentX)
                    y: Math.min(overlay.cropStartY, overlay.cropCurrentY)
                    width: Math.abs(overlay.cropCurrentX - overlay.cropStartX)
                    height: Math.abs(overlay.cropCurrentY - overlay.cropStartY)
                    color: "#224c9aff"
                    border.color: Theme.primary
                    border.width: 2
                    visible: parent.enabled && parent.pressed
                }
            }

            WheelHandler {
                enabled: overlay.kind === "image" && !overlay.cropSelecting
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                    if (delta !== 0)
                        overlay.zoomBy(delta > 0 ? 1 : -1, event.x, event.y);
                }
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingXL * 2
                visible: overlay.errorMessage !== "" && !(overlay.kind === "text" && overlay.textRevision !== "")
                text: overlay.errorMessage
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Theme.spacingM
            visible: overlay.kind === "text" && (overlay.textExternalChanged || overlay.textTruncated || overlay.textLoading || overlay.textSaving || overlay.textError !== "" || overlay.textDirty || overlay.textReadOnlyReason !== "")

            StyledText {
                text: overlay.textExternalChanged ? I18n.tr("File changed on disk", "external modification warning in text viewer") : overlay.textError !== "" ? overlay.textError : overlay.textLoading || overlay.textSaving ? I18n.tr("Loading…", "loading indicator") : overlay.textTruncated ? I18n.tr("File is too large to preview in full", "text preview truncation notice") : overlay.textDirty ? I18n.tr("Unsaved changes", "edited text has unsaved changes") : overlay.textReadOnlyReason
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            DActionButton {
                objectName: "textExternalReloadButton"
                visible: overlay.textExternalChanged
                enabled: !overlay.textLoading && !overlay.textSaving
                iconName: "refresh"
                tooltipText: I18n.tr("Reload from disk", "reload an externally changed text file")
                onClicked: overlay.confirmLeave(() => overlay.loadText())
            }
        }

        RowLayout {
            id: controls

            visible: overlay.kind === "image" || overlay.kind === "pdf"

            enabled: overlay.kind !== "pdf" || overlay.pageView?.ready === true
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Theme.spacingM
            spacing: Theme.spacingXS

            DActionButton {
                iconName: "zoom_out"
                enabled: overlay.zoom > 0.25
                tooltipText: I18n.tr("Zoom out", "tooltip on the button zooming the large preview out")
                onClicked: overlay.zoomBy(-1)
            }

            StyledText {
                Layout.preferredWidth: Theme.spacingXL * 2
                text: Math.round(overlay.zoom * 100) + "%"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                visible: overlay.kind === "image" && overlay.imageCrop !== null
                text: overlay.imageCrop ? overlay.imageCrop.width + " × " + overlay.imageCrop.height : ""
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            DActionButton {
                iconName: "zoom_in"
                enabled: overlay.zoom < 8
                tooltipText: I18n.tr("Zoom in", "tooltip on the button zooming the large preview in")
                onClicked: overlay.zoomBy(1)
            }

            DActionButton {
                visible: overlay.kind === "image"
                iconName: "fit_screen"
                tooltipText: I18n.tr("Fit to window", "fit image to preview window")
                onClicked: overlay.fitImage()
            }

            DActionButton {
                visible: overlay.kind === "image"
                iconName: overlay.cropSelecting ? "close" : "crop"
                tooltipText: overlay.cropSelecting ? I18n.tr("Cancel crop", "cancel selecting an image crop") : I18n.tr("Crop image", "start selecting an image crop")
                onClicked: overlay.beginCrop()
            }

            DActionButton {
                visible: overlay.kind === "image"
                enabled: overlay.originalZoom > 0
                iconName: "photo_size_select_actual"
                tooltipText: I18n.tr("Original size", "show image at its original pixel size")
                onClicked: overlay.showOriginalSize()
            }

            DActionButton {
                visible: overlay.kind === "image"
                iconName: "flip"
                tooltipText: I18n.tr("Flip horizontally", "mirror image horizontally")
                onClicked: overlay.mirrored = !overlay.mirrored
            }

            DActionButton {
                iconName: "restart_alt"
                tooltipText: I18n.tr("Reset the view", "tooltip on the button restoring zoom and rotation")
                onClicked: overlay.reset()
            }

            DActionButton {
                iconName: "rotate_left"
                tooltipText: I18n.tr("Rotate left", "tooltip on the button turning the large preview left")
                onClicked: overlay.rotateBy(-90)
            }

            DActionButton {
                iconName: "rotate_right"
                tooltipText: I18n.tr("Rotate right", "tooltip on the button turning the large preview right")
                onClicked: overlay.rotateBy(90)
            }
        }

        ConfirmDialog {
            id: discardDialog
            title: I18n.tr("Discard unsaved changes?", "confirm leaving edited text")
            message: I18n.tr("Your changes have not been saved.", "confirm leaving edited text")
            confirmText: I18n.tr("Discard", "discard unsaved text changes")
            onConfirmed: {
                overlay.textSaved = overlay.textContent;
                const action = overlay.pendingLeave;
                overlay.pendingLeave = null;
                if (action) action();
            }
            onClosed: overlay.pendingLeave = null
        }

        Shortcut {
            sequences: ["Ctrl+F"]
            enabled: overlay.open && overlay.kind === "text" && overlay.shortcutsActive
            onActivated: {
                overlay.textSearchOpen = true;
                textSearch.focusSearch();
            }
        }

        Shortcut {
            sequences: ["Ctrl+S"]
            enabled: overlay.open && overlay.kind === "text"
            onActivated: overlay.saveText()
        }

        DialogLoader {
            id: imageExportDialogLoader

            NameDialog {
                title: I18n.tr("Export image", "image viewer export dialog title")
                acceptText: I18n.tr("Export", "confirm exporting an image")
                onSubmitted: name => overlay.writeImage(name)
            }
        }

        Shortcut {
            sequences: ["Escape"]
            enabled: overlay.open
            onActivated: overlay.dismiss()
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: overlay.open && overlay.kind === "text" && overlay.textRevision !== "" && !overlay.textExternalChanged
        onTriggered: overlay.checkTextRevision()
    }
}
