pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.Modules

ShellRoot {
    id: fixture
    Item { id: host; width: 800; height: 600 }
    Component { id: component; PreviewPdf { width: 800; height: 600; source: Qt.resolvedUrl("pdf-pages.pdf") } }
    Component { id: sideComponent; PreviewPdfSide { width: 300; height: 500; source: Qt.resolvedUrl("pdf-pages.pdf") } }
    property var viewer: null
    property bool passed: false
    Component.onCompleted: viewer = component.createObject(host)
    TestCase {
        name: "PdfViewer"
        when: fixture.viewer !== null
        function test_navigation_and_search() {
            const viewer = fixture.viewer;
            tryCompare(viewer, "ready", true);
            compare(viewer.pageCount, 2);
            viewer.goToPage(1);
            tryCompare(viewer, "currentPage", 1);
            viewer.goToPage(3);
            compare(viewer.currentPage, 1);
            viewer.showThumbnails = true;
            verify(viewer.showThumbnails);
            viewer.searchText = "needle";
            tryCompare(viewer, "searchCount", 2);
            viewer.searchStep(1);
            viewer.searchStep(1);
            viewer.fitWidth = true;
            verify(viewer.fitScale > 0);
            viewer.angle = 90;
            verify(viewer.fitScale > 0);
            viewer.source = Qt.resolvedUrl("pdf-metadata.pdf");
            tryCompare(viewer, "ready", true);
            tryCompare(viewer, "documentTitle", "Fjord Test PDF");
            compare(viewer.documentAuthor, "Fjord Test Author");
            compare(viewer.documentSubject, "Fjord Test Subject");
            viewer.showMetadata = true;
            verify(viewer.showMetadata);
            const side = sideComponent.createObject(host);
            tryCompare(side, "ready", true);
            compare(side.pageCount, 2);
            side.currentPage = 1;
            compare(side.currentPage, 1);
            side.source = Qt.resolvedUrl("pdf-metadata.pdf");
            compare(side.currentPage, 0);
            side.destroy();
            viewer.source = "";
            compare(viewer.showMetadata, false);
            compare(viewer.searchText, "");
            compare(viewer.showThumbnails, false);
            fixture.passed = true;
        }
        function cleanupTestCase() { if (fixture.passed) console.log("FIXTURE PASS"); Qt.callLater(Qt.quit); }
    }
}
