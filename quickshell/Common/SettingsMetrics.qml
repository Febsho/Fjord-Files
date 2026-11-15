pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property real sidebarWidth: 270
    readonly property real compactBreakpoint: 700
    readonly property real contentMaxWidth: 920
    readonly property real windowWidth: 1100
    readonly property real windowHeight: 940
    readonly property real windowMinWidth: 500
    readonly property real windowMinHeight: 400
    readonly property real pagePaddingV: Theme.spacingXL + Theme.densityStepM
    readonly property real pageHeaderHeight: Theme.fontSizeXXLarge + Theme.spacingXL + Theme.spacingM
    readonly property real paneMargin: Theme.windowInset
    readonly property real panePadding: Theme.spacingXL
    readonly property real paneRadius: Theme.cornerRadiusL
    readonly property real rowPaddingH: Theme.spacingL
    readonly property real rowPaddingV: Theme.spacingM + Theme.densityStepS
    readonly property real rowMinHeight: Math.max(Theme.listItemHeight + Theme.densityStepM, Theme.buttonHeightS + Theme.spacingXS)
    readonly property real rowMinHeightTwoLine: Theme.listItemTwoLineHeight + Theme.densityStepM
    readonly property real cardGap: Theme.spacingL + Theme.densityStepS
    readonly property real rowContentSpacing: Theme.spacingL
    readonly property real sectionLabelTopGap: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepS)
    readonly property real sectionLabelBottomGap: Theme.spacingM
    readonly property real navIconSize: Theme.iconSizeLarge
    readonly property real navItemMinHeight: rowMinHeight
    readonly property real sidebarGroupGap: Theme.spacingM
    readonly property real buttonGroupCompactThreshold: Theme.spacingXL * 8
    readonly property real dropdownWidth: 220
    readonly property real dropdownChrome: Theme.spacingS * 2 + Theme.spacingXS + Theme.iconSize + Theme.spacingM
    readonly property real disabledOpacity: 0.38
    readonly property real highlightBlend: 0.2
    readonly property color paneColor: Theme.withAlpha(Theme.surfaceContainerLow, Theme.floatingWindowForegroundAlpha)
    readonly property color sidebarRowColor: "transparent"
    readonly property color rowColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.isLightMode ? 0.72 : 0.58)
    readonly property color controlSurface: Theme.chipSurfaceNested
    readonly property color selectedRowColor: Theme.withAlpha(Theme.primary, Theme.isLightMode ? 0.13 : 0.20)
    readonly property int transitionDuration: Theme.expressiveDurations.expressiveFastSpatial
    readonly property int fadeDuration: Theme.expressiveDurations.expressiveEffects
    readonly property int flashHold: 1200
}
