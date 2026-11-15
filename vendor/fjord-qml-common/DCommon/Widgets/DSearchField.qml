import QtQuick
import qs.DCommon.Common

DTextField {
    fieldHeight: Style.fieldHeightLarge
    cornerRadius: Style.pillControls ? Style.fullRadius(width, height) : Style.cornerRadiusL
    normalBorderColor: Style.outlineVariant
    focusedBorderColor: Style.focusRingWidth > 0 ? Style.focusRingColor : normalBorderColor
    borderWidth: Style.outlineWidth
    focusedBorderWidth: Math.max(borderWidth, Style.focusRingWidth)
    placeholderColor: Style.surfaceTextSecondary
    leftIconName: "search"
    hidePlaceholderOnFocus: false
    showClearButton: true

    // The search icon and its padding sit outside the inner TextInput. Keep
    // that leading area clickable so clicking the visible start of the field
    // places the caret at the beginning instead of doing nothing.
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.leftPadding
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.IBeamCursor
        onPressed: {
            parent.forceActiveFocus();
            parent.cursorPosition = 0;
        }
    }
}
