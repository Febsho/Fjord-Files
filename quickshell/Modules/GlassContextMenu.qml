pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.FileBrowser
import qs.DCommon.Common as DC
import qs.DCommon.Widgets

FileMenu {
    background: GlassPopover {
        id: surface

        DC.ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel2
            fallbackOffset: Theme.spacingXS
            targetRadius: Theme.cornerRadiusL
            targetColor: surface.materialColor
            borderColor: Theme.outlineMedium
            borderWidth: Theme.layerOutlineWidth
            shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
        }
    }
}
