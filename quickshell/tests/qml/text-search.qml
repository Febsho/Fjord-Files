pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.Common
import qs.Services
import qs.Modules
import qs.DCommon.Common as DC

ShellRoot {
    id: fixture
    property bool ready: false
    readonly property var log: Log.scoped("fixture")
    Item {
        width: 800; height: 300
        TextEdit { id: editor; text: "one two one" }
        TextSearchBar { id: bar; width: 700; editor: editor }
    }
    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.I18n.backend = I18n;
        ready = true;
    }
    TestCase {
        name: "TextSearch"
        when: fixture.ready
        function test_searchReplace() {
            bar.query = "one";
            editor.cursorPosition = 0;
            verify(bar.find(1));
            compare(editor.selectionStart, 0);
            verify(bar.find(1));
            compare(editor.selectionStart, 8);
            verify(bar.find(1));
            compare(editor.selectionStart, 0);
            verify(bar.find(-1));
            compare(editor.selectionStart, 8);
            bar.replacement = "three";
            verify(bar.replaceCurrent());
            compare(editor.text, "one two three");
            editor.readOnly = true;
            verify(!bar.replaceCurrent());
            compare(editor.text, "one two three");
            bar.query = "missing";
            verify(!bar.find(1));
        }
        function cleanupTestCase() {
            fixture.log.info("FIXTURE PASS");
            Qt.callLater(Qt.quit);
        }
    }
}
