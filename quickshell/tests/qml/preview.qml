pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.Common
import qs.Services
import qs.Modules
import qs.DCommon.Common as DC
import qs.DCommon.FileBrowser

ShellRoot {
    id: fixture

    readonly property var log: Log.scoped("fixture")
    property int failures: 0
    property var view: null
    property bool ready: false
    property bool pdfChecked: false
    property bool longLineChecked: false
    property bool mediaChecked: false

    function check(label, actual, expected) {
        const ok = JSON.stringify(actual) === JSON.stringify(expected);
        if (!ok) {
            failures++;
            log.error(`FAIL ${label}: got ${JSON.stringify(actual)} want ${JSON.stringify(expected)}`);
            return;
        }
        log.info(`ok ${label}`);
    }

    function finish() {
        if (failures === 0)
            log.info("FIXTURE PASS");
        Qt.callLater(Qt.quit);
    }

    Item {
        id: host

        width: 800
        height: 600
    }

    Component {
        id: overlayComponent

        PreviewOverlay {
            width: host.width
            height: host.height
        }
    }

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;

        const view = overlayComponent.createObject(host);
        fixture.view = view;

        view.present({
            "path": "/nonexistent/photo.png",
            "name": "photo.png",
            "mime": "application/octet-stream"
        });
        check("an unsupported format does not open it", view.open, false);

        let archiveReply;
        view.archiveReader = (path, callback) => { archiveReply = callback; };
        view.present({"path": "/example.zip", "name": "example.zip", "viewer": "archive"});
        check("archive opens and loads", [view.kind, view.archiveLoading], ["archive", true]);
        archiveReply({"entries": [{"path": "dir/file.txt", "size": 3, "dir": false}, {"path": "root.txt", "size": 1, "dir": false}], "truncated": true});
        check("archive shows inferred directory", view.archiveChildren.map(e => e.name), ["dir", "root.txt"]);
        view.archiveFolder = "dir";
        check("archive navigates into directory", [view.archiveChildren[0].name, view.archiveTruncated], ["file.txt", true]);
        view.archiveSearch = "FILE.TXT";
        check("archive search finds nested paths case insensitively", view.archiveChildren.map(e => e.path), ["dir/file.txt"]);
        view.archiveSelection = "dir/file.txt";
        view.archiveSearch = "root";
        check("changing search clears selection", [view.archiveSelection, view.archiveChildren[0].path], ["", "root.txt"]);
        view.archiveSearch = "";
        check("clearing search restores folder", view.archiveChildren[0].path, "dir/file.txt");
        view.dismiss();

        let reply;
        view.textReader = (path, limit, callback) => { reply = callback; };
        view.present({"path": "/notes.txt", "name": "notes.txt", "mime": "text/plain"});
        check("text opens in quick look", [view.open, view.kind, view.textLoading], [true, "text", true]);
        reply({"text": "hello", "truncated": true});
        check("text result is displayed with truncation", [view.textContent, view.textTruncated, view.textLoading], ["hello", true, false]);
        view.present({"path": "/old.txt", "name": "old.txt", "mime": "text/plain"});
        const staleReply = reply;
        view.present({"path": "/new.txt", "name": "new.txt", "mime": "text/plain"});
        staleReply({"text": "stale"});
        check("stale text result is ignored", [view.textContent, view.textLoading], ["", true]);
        reply({"binary": true});
        check("binary content is rejected", view.textError !== "", true);
        view.dismiss();

        view.textReader = (path, limit, callback) => callback({"text": "before", "revision": "ext1"});
        view.textRevisionReader = (path, callback) => callback({"revision": "ext1"});
        view.present({"path": "/external.txt", "name": "external.txt", "mime": "text/plain"});
        view.checkTextRevision();
        check("unchanged text revision stays clear", view.textExternalChanged, false);
        view.textRevisionReader = (path, callback) => callback({"revision": "ext2"});
        view.checkTextRevision();
        check("external text edits are detected", view.textExternalChanged, true);
        const reloadButton = fixture.findItem(view, item => item.objectName === "textExternalReloadButton");
        check("changed text can be reloaded", reloadButton?.visible, true);
        view.textReader = (path, limit, callback) => callback({"text": "after", "revision": "ext2"});
        reloadButton.clicked();
        check("reload reads current disk contents", [view.textContent, view.textExternalChanged], ["after", false]);
        view.dismiss();

        view.textReader = (path, limit, callback) => { reply = callback; };
        view.present({"path": "/editable.txt", "name": "editable.txt", "mime": "text/plain"});
        reply({"text": "original", "revision": "rev1"});
        view.textSearchOpen = true;
        const searchBar = fixture.findItem(view, item => item.objectName === "previewTextSearch");
        check("text search is available", searchBar !== null, true);
        const wrapButton = fixture.findItem(view, item => item.objectName === "textWrapButton");
        check("word wrap button is available", wrapButton !== null, true);
        const editButton = fixture.findItem(view, item => item.objectName === "textEditButton");
        check("edit mode button is available", editButton?.visible, true);
        editButton.clicked();
        check("text enters explicit edit mode", view.textEditMode, true);
        wrapButton.clicked();
        check("word wrap can be disabled", view.textWrap, false);
        wrapButton.clicked();
        check("word wrap can be enabled", view.textWrap, true);
        searchBar.query = "original";
        searchBar.replacement = "edited";
        searchBar.editor.cursorPosition = 0;
        searchBar.find(1);
        searchBar.replaceCurrent();
        check("replace changes editor and marks it dirty", [view.textContent, view.textDirty], ["edited", true]);
        let saveReply;
        view.textWriter = (path, revision, text, callback) => {
            fixture.check("save sends revision and edited text", [path, revision, text], ["/editable.txt", "rev1", "edited"]);
            saveReply = callback;
        };
        view.saveText();
        check("save retains changes while pending", [view.textSaving, view.textDirty], [true, true]);
        saveReply({"error": "file changed on disk"});
        check("conflict retains edited text", [view.textContent, view.textDirty, view.textError], ["edited", true, "file changed on disk"]);
        view.saveText();
        saveReply({"revision": "rev2", "path": "/editable.txt.edited"});
        check("successful save switches to the new file", [view.textDirty, view.textRevision, view.path], [false, "rev2", "/editable.txt.edited"]);
        view.dismiss();

        view.textReader = (path, limit, callback) => callback({"text": "package main\n// comment\nfunc main() { println(\"<hello>\") }", "revision": "rev3"});
        view.present({"path": "/sample.go", "name": "sample.go", "mime": "text/plain"});
        check("source extension selects a highlighter", view.syntaxLanguage, "go");
        check("syntax preview escapes markup", view.syntaxMarkup.includes("&lt;hello&gt;"), true);
        check("keywords and literals receive syntax colors", view.syntaxMarkup.includes("<span style=\"color:"), true);
        const syntaxPreview = fixture.findItem(view, item => item.objectName === "textSyntaxPreview");
        const textEditButton = fixture.findItem(view, item => item.objectName === "textEditButton");
        check("highlighted text is shown by default", syntaxPreview?.visible, true);
        check("edit mode is available for supported text", textEditButton?.visible, true);
        textEditButton.clicked();
        check("edit mode displays the plain editor", [view.textEditMode, syntaxPreview.visible], [true, false]);
        textEditButton.clicked();
        view.dismiss();
        view.textReader = (path, limit, callback) => { reply = callback; };

        view.textFallbackReader = (path, limit, callback) => callback({"text": "partial", "truncated": true});
        view.present({"path": "/large.txt", "name": "large.txt", "mime": "text/plain"});
        reply({"error": "file is too large to edit"});
        check("large file falls back to read-only preview", [view.textContent, view.textTruncated, view.textRevision], ["partial", true, ""]);
        view.dismiss();
        view.textFallbackReader = (path, limit, callback) => callback({"text": "line1\r\nline2", "truncated": false});
        view.present({"path": "/windows.txt", "name": "windows.txt", "mime": "text/plain"});
        reply({"error": "file is not supported UTF-8 text (only LF line endings are supported)"});
        check("CRLF file falls back to read-only preview", [view.textRevision, view.textReadOnlyReason !== ""], ["", true]);
        view.dismiss();

        let imageReply;
        view.imageReader = (path, callback) => { imageReply = callback; };
        view.present({"path": "/missing.png", "name": "missing.png", "mime": "image/png"});
        imageReply({"error": "decoder failed"});
        check("isolated decoder failure is visible", view.errorMessage, "decoder failed");
        check("isolated failure does not load original", view.isolatedImage, "");
        view.dismiss();
        view.present({
            "path": "/nonexistent/photo.png",
            "name": "photo.png",
            "mime": "image/png"
        });
        check("an image opens it", [view.open, view.kind], [true, "image"]);
        view.imageWidth = 1920;
        view.imageHeight = 1080;
        check("image dimensions are shown", view.imageDetails, "1920 × 1080");
        check("the view starts unzoomed and upright", [view.zoom, view.angle, view.panX, view.panY], [1, 0, 0, 0]);

        let imageExportParams;
        view.imageCrop = {"x": 12, "y": 24, "width": 300, "height": 200};
        view.angle = 90;
        view.mirrored = true;
        view.imageExportWriter = (params, callback) => { imageExportParams = params; };
        view.writeImage("copy.png");
        check("image export writes a new cropped transformed PNG", imageExportParams, {
            "path": "/nonexistent/photo.png",
            "destination": "/nonexistent/copy.png",
            "x": 12,
            "y": 24,
            "width": 300,
            "height": 200,
            "angle": 90,
            "mirror": true
        });
        check("image export reports its pending state", view.imageExporting, true);
        view.imageExporting = false;
        view.imageCrop = null;
        view.angle = 0;
        view.mirrored = false;

        view.zoomBy(1);
        check("zooming in steps up", view.zoom, 1.25);
        view.zoomBy(-1);
        check("zooming out steps back", view.zoom, 1);

        for (let step = 0; step < 20; step++)
            view.zoomBy(1);
        check("zooming in stops at the ceiling", view.zoom, 8);
        for (let step = 0; step < 40; step++)
            view.zoomBy(-1);
        check("zooming out stops at the floor", view.zoom, 0.25);

        view.rotateBy(90);
        check("rotating right turns a quarter", view.angle, 90);
        view.rotateBy(-180);
        check("rotating left turns back and past zero", view.angle, 270);
        view.rotateBy(90);
        check("a full turn normalizes to zero", view.angle, 0);

        view.reset();
        view.zoomAt(2, view.imageStage.width * 0.75, view.imageStage.height / 2);
        check("zoom follows the pointer", view.panX < 0, true);
        view.mirrored = true;
        view.reset();
        check("reset clears mirroring", view.mirrored, false);
        view.zoomBy(1);
        view.panTo(100000, 100000);
        check("panning stops at the image edge", [view.panX > 0, view.panY > 0], [true, true]);
        view.panTo(-100000, -100000);
        check("panning stops at the other edge", [view.panX < 0, view.panY < 0], [true, true]);

        view.reset();
        check("resetting drops zoom, angle and pan", [view.zoom, view.angle, view.panX, view.panY], [1, 0, 0, 0]);

        fixture.ready = true;
    }

    function findItem(item, predicate) {
        for (const child of item.children ?? []) {
            if (predicate(child))
                return child;
            const match = findItem(child, predicate);
            if (match)
                return match;
        }
        return null;
    }

    TestCase {
        name: "PdfPreview"
        when: fixture.ready

        function test_long_line_wrap() {
            const view = fixture.view;
            view.textReader = (path, limit, callback) => callback({"text": "long ".repeat(500), "revision": "test"});
            view.present({"path": "/long-line.txt", "name": "long-line.txt", "mime": "text/plain"});
            const scroller = fixture.findItem(view, item => item.objectName === "textScroller");
            verify(scroller !== null);
            view.textWrap = false;
            tryVerify(() => scroller.contentWidth > scroller.width * 2);
            const editor = fixture.findItem(view, item => item.objectName === "textEditor");
            verify(editor !== null);
            editor.forceActiveFocus();
            editor.cursorPosition = editor.length;
            tryVerify(() => editor.cursorRectangle.x > 100);
            scroller.revealCursor(true);

            tryVerify(() => scroller.contentX > 100);
            editor.cursorPosition = 0;
            tryVerify(() => editor.cursorRectangle.x < 1);
            scroller.revealCursor(true);

            tryVerify(() => scroller.contentX <= editor.x);
            view.textWrap = true;
            tryVerify(() => scroller.contentWidth <= scroller.width + 1);
            view.dismiss();
            fixture.longLineChecked = true;
        }

        function test_media() {
            const view = fixture.view;
            view.present({"path": FilePaths.fromUrl(Qt.resolvedUrl("preview.wav")), "name": "preview.wav", "mime": "audio/wav"});

            compare(view.kind, "media");
            if (view.mediaView === null) {

                verify(view.errorMessage.indexOf("Qt Multimedia") >= 0);
                view.dismiss();
                fixture.mediaChecked = true;
                return;
            }

            tryVerify(() => view.mediaView.player.duration > 0);
            const sideComponent = Qt.createComponent(Qt.resolvedUrl("Modules/PreviewMediaSide.qml"));

            compare(sideComponent.status, Component.Ready);
            const side = sideComponent.createObject(host, {"width": 300, "height": 450, "source": Qt.resolvedUrl("preview.wav")});

            tryVerify(() => side.player.duration > 0);

            compare(side.player.playbackState, 0);

            side.player.audioOutput.volume = 0;
            side.player.play();

            tryCompare(side.player, "playbackState", 1);
            side.source = Qt.resolvedUrl("preview-tags.wav");

            tryCompare(side.player, "playbackState", 0);
            side.destroy();

            compare(view.errorMessage, "");

            compare(view.mediaView.video, false);
            view.mediaView.player.pause();

            compare(view.mediaView.player.playbackState, 2);
            view.present({"path": FilePaths.fromUrl(Qt.resolvedUrl("preview-tags.wav")), "name": "preview-tags.wav", "mime": "audio/wav"});

            tryCompare(view.mediaView, "mediaTitle", "Fjord Test Title");

            compare(view.mediaView.mediaAuthor, "Fjord Test Artist");

            compare(view.mediaView.mediaAlbum, "Fjord Test Album");
            view.present({"path": FilePaths.fromUrl(Qt.resolvedUrl("preview.mp4")), "name": "preview.mp4", "mime": "video/mp4"});

            compare(view.mediaView.video, true);

            tryVerify(() => view.mediaView.player.hasVideo);

            compare(view.errorMessage, "");
            const volume = fixture.findItem(view, item => item.objectName === "mediaVolume");
            const speed = fixture.findItem(view, item => item.objectName === "mediaRate");
            const audio = fixture.findItem(view, item => item.objectName === "mediaAudioTracks");
            const subtitles = fixture.findItem(view, item => item.objectName === "mediaSubtitleTracks");

            verify(volume !== null && speed !== null && audio !== null && subtitles !== null);

            compare(subtitles.enabled, false);
            view.mediaView.audioOutput.volume = 0.4;

            compare(volume.value.toFixed(1), "0.4");
            speed.activated(4);

            compare(view.mediaView.player.playbackRate, 1.5);
            view.present({"path": FilePaths.fromUrl(Qt.resolvedUrl("preview-tracks.mkv")), "name": "preview-tracks.mkv", "mime": "video/x-matroska"});

            tryCompare(view.mediaView.player, "hasVideo", true);

            tryVerify(() => view.mediaView.player.audioTracks.length === 2 && view.mediaView.player.subtitleTracks.length === 1);

            compare(audio.enabled, true);

            compare(subtitles.enabled, true);
            audio.activated(2);

            compare(view.mediaView.player.activeAudioTrack, 1);
            subtitles.activated(1);

            compare(view.mediaView.player.activeSubtitleTrack, 0);

            // Subtitle track selection is testable here; actual subtitle rendering
            // requires a working video output and remains to be checked interactively.
            subtitles.activated(0);

            compare(view.mediaView.player.activeSubtitleTrack, -1);
            view.present({"path": FilePaths.fromUrl(Qt.resolvedUrl("missing.mp4")), "name": "missing.mp4", "mime": "video/mp4"});

            compare(view.mediaView.video, true);

            tryVerify(() => view.errorMessage !== "");
            view.dismiss();

            compare(view.mediaView, null);
            fixture.mediaChecked = true;
        }

        function test_office_preview_loader() {
            view.officePreviewReader = (path, callback) => callback({"path": FilePaths.fromUrl(Qt.resolvedUrl("pdf-pages.pdf"))});
            view.present({"path": "/sample.docx", "name": "sample.docx", "mime": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "viewer": "office"});
            compare(view.kind, "office");
            tryVerify(() => view.officeView !== null);
            tryVerify(() => view.officeView.pdfView?.ready === true);
            compare(view.officeView.pdfView.pageCount > 0, true);
            view.dismiss();
            view.officePreviewReader = (path, callback) => DuxFilesService.call("files.officePreview", {"path": path}, callback);
        }

        function test_optional_pdf() {
            const view = fixture.view;
            view.present({
                "path": FilePaths.fromUrl(Qt.resolvedUrl("preview.pdf")),
                "name": "preview.pdf",
                "mime": "application/pdf"
            });
            compare(view.open, true);
            compare(view.kind, "pdf");

            if (PdfService.available) {
                verify(view.pageView !== null);
                tryCompare(view.pageView, "ready", true);
                compare(view.errorMessage, "");
                view.zoom = 2;
                compare(view.pageView.zoom, 2);
                view.angle = 90;
                compare(view.pageView.angle, 90);

                view.present({
                    "path": FilePaths.fromUrl(Qt.resolvedUrl("missing.pdf")),
                    "name": "missing.pdf",
                    "mime": "application/pdf"
                });
                tryCompare(view.pageView, "failed", true);
                compare(view.errorMessage, "This file could not be opened");
            } else {
                compare(PdfService.unavailable, true);
                compare(view.pageView, null);
                compare(view.errorMessage, "PDF preview is not available. Install Qt PDF support to view this file.");
            }

            const label = fixture.findItem(view, item => item.text === view.errorMessage);
            verify(label !== null);
            compare(label.visible, true);
            view.dismiss();
            compare(view.open, false);
            compare(view.entry, null);
            compare(view.errorMessage, "");
            view.imageReader = (path, callback) => callback({"fullWidth": 1, "fullHeight": 1, "url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"});
            view.present({
                "path": FilePaths.fromUrl(Qt.resolvedUrl("preview.png")),
                "name": "preview.png",
                "mime": "image/png"
            });
            compare(view.kind, "image");
            compare(view.open, true);
            compare(view.pageView, null);
            const image = fixture.findItem(view, item => item.source !== undefined && item.paintedWidth !== undefined);
            verify(image !== null);
            tryCompare(image, "status", Image.Ready);
            compare(view.errorMessage, "");
            view.imageReader = (path, callback) => callback({"fullWidth": 2048, "fullHeight": 1024, "url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"});
            view.present({"path": "/preview.png", "name": "preview.png", "mime": "image/png"});
            tryCompare(image, "status", Image.Ready);
            compare(view.errorMessage, "");
            compare(view.imageWidth, 2048);
            compare(view.imageHeight, 1024);
            tryVerify(() => view.originalZoom > 0);
            const original = view.originalZoom;
            view.showOriginalSize();
            compare(view.zoom, original);
            view.fitImage();
            compare(view.zoom, 1);
            fixture.pdfChecked = true;
        }

        function cleanupTestCase() {
            if (!fixture.pdfChecked || !fixture.longLineChecked || !fixture.mediaChecked)
                fixture.failures++;
            fixture.view.destroy();
            fixture.finish();
        }
    }
}
