pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Common as DC

ShellRoot {
    id: fixture
    readonly property var log: Log.scoped("fixture")
    property bool ready: false

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.I18n.backend = I18n;
        SettingsData.colorSource = "auto";
        SettingsData.themeMode = "auto";
        ready = true;
    }

    TestCase {
        name: "NoctaliaPalette"
        when: fixture.ready

        function test_palette_and_fallback() {
            tryCompare(Theme, "noctaliaColorsAvailable", true);
            compare(Theme.isLightMode, false);
            compare(Theme.currentThemeData.primary, "#123456");
            SettingsData.themeMode = "light";
            compare(Theme.noctaliaColorsAvailable, false);
            compare(Theme.isLightMode, true);
        }

        function cleanupTestCase() {
            fixture.log.info("FIXTURE PASS");
            Qt.callLater(Qt.quit);
        }
    }
}
