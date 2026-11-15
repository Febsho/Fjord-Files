import QtQuick
import qs.Common

GlassSurface {
    baseColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.floatingWindowForegroundAlpha * 0.28)
    highlightsEnabled: false
    edgeLightingEnabled: false
    topLeftRadius: Theme.cornerRadiusL
    topRightRadius: Theme.cornerRadiusL
    bottomLeftRadius: Theme.cornerRadiusL
    bottomRightRadius: Theme.cornerRadiusL
}
