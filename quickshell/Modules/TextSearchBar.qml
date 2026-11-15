pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common

RowLayout {
    id: root

    required property var editor
    property bool replaceEnabled: true
    property alias query: search.text
    property alias replacement: replacement.text
    readonly property bool found: editor && query !== "" && editor.selectedText === query

    signal closeRequested
    signal selectionFound()

    function focusSearch() {
        search.forceActiveFocus();
        search.selectAll();
    }

    function find(direction) {
        if (!editor || query === "")
            return false;
        const content = editor.text;
        let at;
        if (direction < 0) {
            const start = editor.selectionStart < editor.selectionEnd ? editor.selectionStart : editor.cursorPosition;
            at = start > 0 ? content.lastIndexOf(query, start - 1) : -1;
            if (at < 0)
                at = content.lastIndexOf(query);
        } else {
            const start = editor.selectionStart < editor.selectionEnd ? editor.selectionEnd : editor.cursorPosition;
            at = content.indexOf(query, start);
            if (at < 0)
                at = content.indexOf(query);
        }
        if (at < 0)
            return false;
        editor.select(at, at + query.length);
        selectionFound();
        return true;
    }

    function replaceCurrent() {
        if (!editor || !replaceEnabled || editor.readOnly || query === "")
            return false;
        if (!found)
            return find(1);
        const start = editor.selectionStart;
        editor.remove(start, editor.selectionEnd);
        editor.insert(start, root.replacement);
        editor.cursorPosition = start + root.replacement.length;
        return true;
    }

    TextField {
        id: search
        objectName: "textSearchQuery"
        Layout.fillWidth: true
        Layout.minimumWidth: 80
        placeholderText: I18n.tr("Find", "text viewer search")
        selectByMouse: true
        onAccepted: root.find(1)
    }
    ToolButton {
        text: "↑"
        enabled: root.query !== ""
        Accessible.name: I18n.tr("Previous result", "text viewer search")
        onClicked: root.find(-1)
    }
    ToolButton {
        text: "↓"
        enabled: root.query !== ""
        Accessible.name: I18n.tr("Next result", "text viewer search")
        onClicked: root.find(1)
    }
    TextField {
        id: replacement
        objectName: "textSearchReplacement"
        Layout.fillWidth: true
        Layout.minimumWidth: 80
        visible: root.replaceEnabled && !root.editor.readOnly
        placeholderText: I18n.tr("Replace", "text viewer search")
        selectByMouse: true
    }
    Button {
        visible: root.replaceEnabled && !root.editor.readOnly
        enabled: root.query !== ""
        text: I18n.tr("Replace", "text viewer search action")
        onClicked: root.replaceCurrent()
    }
    ToolButton {
        text: "×"
        Accessible.name: I18n.tr("Close", "close text search")
        onClicked: root.closeRequested()
    }
}
