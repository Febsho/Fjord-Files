import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string hint: ""
    property string accent: ""
    property bool active: false
    property bool highlighted: false
    property bool isFirstInGroup: true
    property bool isLastInGroup: true
    property int matchCount: -1

    signal clicked

    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: matchCount > 0 ? I18n.tr("%1, %2 matches", "accessible description of a settings page while searching, name then count").arg(hint).arg(matchCount) : hint
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.clicked();
            event.accepted = true;
            break;
        }
    }

    readonly property color badgeColor: Theme.withAlpha(Theme.primary, root.active ? 0.14 : 0)
    readonly property color glyphColor: root.active ? Theme.primary : Theme.surfaceVariantText
    readonly property real topRadius: isFirstInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
    readonly property real bottomRadius: isLastInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius

    width: parent?.width ?? 0
    height: SettingsMetrics.navItemMinHeight
    topLeftRadius: topRadius
    topRightRadius: topRadius
    bottomLeftRadius: bottomRadius
    bottomRightRadius: bottomRadius
    border.width: 0
    border.color: "transparent"
    color: {
        if (active)
            return SettingsMetrics.selectedRowColor;
        if (highlighted)
            return Theme.withAlpha(Theme.surfaceText, Theme.isLightMode ? 0.055 : 0.10);
        return SettingsMetrics.sidebarRowColor;
    }

    Behavior on color {
        enabled: Theme.animationsEnabled
        ColorAnimation {
            duration: SettingsMetrics.fadeDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    Rectangle {
        anchors.fill: parent
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
        color: Theme.surfaceText
        opacity: mouseArea.pressed ? Theme.stateLayerHover : (mouseArea.containsMouse ? Theme.stateLayerHover * 0.45 : 0)

        Behavior on opacity {
            enabled: Theme.animationsEnabled
            NumberAnimation {
                duration: SettingsMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.focusRingWidth / 2
        topLeftRadius: Math.max(0, root.topRadius - Theme.focusRingWidth / 2)
        topRightRadius: topLeftRadius
        bottomLeftRadius: Math.max(0, root.bottomRadius - Theme.focusRingWidth / 2)
        bottomRightRadius: bottomLeftRadius
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRingColor
        visible: root.activeFocus
    }

    Rectangle {
        id: iconCircle
        width: SettingsMetrics.navIconSize
        height: SettingsMetrics.navIconSize
        radius: Theme.cornerRadiusS
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        color: root.badgeColor

        Behavior on color {
            enabled: Theme.animationsEnabled
            ColorAnimation {
                duration: SettingsMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        DIcon {
            anchors.centerIn: parent
            name: root.iconName
            size: Theme.iconSizeSmall
            color: root.glyphColor
        }
    }

    StyledText {
        id: countBadge
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        visible: root.matchCount > 0
        text: root.matchCount
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.primary
    }

    Column {
        id: textColumn
        anchors.left: iconCircle.right
        anchors.leftMargin: Theme.spacingS
        anchors.right: countBadge.visible ? countBadge.left : parent.right
        anchors.rightMargin: countBadge.visible ? Theme.spacingM : Theme.spacingL
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        StyledText {
            width: parent.width
            text: root.title
            font.pixelSize: Theme.fontSizeMedium
            font.weight: root.active ? Theme.fontWeightMedium : Theme.fontWeight
            color: root.active ? Theme.primary : Theme.surfaceText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }

        StyledText {
            width: parent.width
            text: root.hint
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            visible: false
            horizontalAlignment: Text.AlignLeft
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
