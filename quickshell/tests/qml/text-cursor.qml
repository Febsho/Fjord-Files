pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Common
import qs.Modules
import qs.DCommon.Common as DC

ShellRoot {
    id: fixture
    property bool ready: false
    property bool passed: false
    Window {
        id: surface
        width: 800; height: 600; visible: true
        PreviewOverlay {
            id: viewer
            anchors.fill: parent
            embedded: true
            textReader: (path, limit, callback) => callback({"text": "long ".repeat(500), "revision": "test"})
        }
    }
    function findItem(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const result = findItem(child, name);
            if (result) return result;
        }
        return null;
    }
    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        viewer.present({"path": "/long.txt", "name": "long.txt", "mime": "text/plain"});
        viewer.textEditMode = true;
        viewer.textWrap = false;
        ready = true;
    }
    TestCase {
        name: "TextCursor"
        when: fixture.ready && surface.visible
        function test_cursorFollowsKeyboard() {
            const editor = fixture.findItem(viewer, "textEditor");
            const scroll = fixture.findItem(viewer, "textScroller");
            verify(editor !== null && scroll !== null);
            surface.requestActivate();
            editor.forceActiveFocus();
            tryCompare(editor, "activeFocus", true);
            keyClick(Qt.Key_End, Qt.ControlModifier);
            tryCompare(editor, "cursorPosition", editor.length);
            tryVerify(() => scroll.contentX > 100);
            keyClick(Qt.Key_Home, Qt.ControlModifier);
            tryCompare(editor, "cursorPosition", 0);
            tryVerify(() => scroll.contentX <= editor.x);
            keyClick(Qt.Key_A);
            verify(viewer.textContent.startsWith("a"));
            viewer.textContent = "alpha\nbeta\ngamma";
            viewer.textLineNumbers = false;
            const gutter = fixture.findItem(viewer, "textLineNumberGutter");
            const lineNumbersButton = fixture.findItem(viewer, "textLineNumbersButton");
            verify(gutter !== null && lineNumbersButton !== null);
            verify(lineNumbersButton.visible && lineNumbersButton.enabled);
            viewer.textLineNumbers = true;
            tryCompare(gutter, "text", "1\n2\n3");
            verify(gutter.visible);
            verify(editor.x > gutter.x);
            viewer.textWrap = true;
            tryCompare(gutter, "visible", false);
            verify(!lineNumbersButton.enabled);
            fixture.passed = true;
        }
        function cleanupTestCase() { if (fixture.passed) console.log("FIXTURE PASS"); Qt.callLater(Qt.quit); }
    }
}
