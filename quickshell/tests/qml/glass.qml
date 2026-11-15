pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Common
import qs.Modules
import qs.Services
import qs.DCommon.Common as DC

ShellRoot {
    id: fixture

    readonly property var log: Log.scoped("fixture")
    property int failures: 0
    property bool renderReady: false
    property int renderChecks: 0

    function check(label, condition) {
        if (condition) {
            log.info(`ok ${label}`);
            return;
        }
        failures++;
        log.error(`FAIL ${label}`);
    }

    function finish() {
        renderDelay.start();
    }

    GlassSurface {
        id: surface

        width: 320
        height: 180
        baseColor: "#e8eaf0"
    }

    Window {
        id: renderWindow

        width: 720
        height: 240
        color: "#202028"
        visible: true

        Rectangle {
            id: refractiveSource

            x: 360
            y: 20
            width: 320
            height: 180
            property color firstColor: "#e85477"
            property int sourceRevision: 0
            gradient: Gradient {
                GradientStop { position: 0; color: refractiveSource.firstColor }
                GradientStop { position: 1; color: "#4576d0" }
            }

            Text {
                anchors.centerIn: parent
                text: "FJORD   DSC_0042.JPG"
                color: "#ffffff"
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }
        }

        GlassSurface {
            id: refractiveSurface

            x: 400
            y: 80
            width: 220
            height: 48
            baseColor: Theme.withAlpha("#202028", 0.54)
            refractionSource: refractiveSource
            refractionLive: false
            refractionRevision: refractiveSource.sourceRevision
        }
    }

    Timer {
        id: renderDelay
        interval: 250
        onTriggered: fixture.renderReady = true
    }

    TestCase {
        name: "GlassRefraction"
        when: fixture.renderReady && renderWindow.visible

        function test_localSourceRendersThroughSurface() {
            fixture.renderChecks++;
            const refracted = grabImage(renderWindow.contentItem);
            fixture.check("refraction surface renders", refracted.width > 0 && refracted.height > 0);
            const lightCapturePath = Quickshell.env("FJORD_GLASS_CAPTURE_LIGHT_PATH") || "";
            const darkCapturePath = Quickshell.env("FJORD_GLASS_CAPTURE_DARK_PATH") || "";
            if (lightCapturePath !== "" || darkCapturePath !== "") {
                const previousTheme = SettingsData.themeMode;
                SettingsData.themeMode = "light";
                wait(60);
                if (lightCapturePath !== "")
                    grabImage(renderWindow.contentItem).save(lightCapturePath);
                SettingsData.themeMode = "dark";
                wait(60);
                if (darkCapturePath !== "")
                    grabImage(renderWindow.contentItem).save(darkCapturePath);
                SettingsData.themeMode = previousTheme;
                wait(60);
            }
            if (Quickshell.env("FJORD_GLASS_VERIFY_RENDERING") === "1") {
                refractiveSource.firstColor = "#20a861";
                refractiveSource.sourceRevision++;
                wait(80);
                const refreshed = grabImage(renderWindow.contentItem);
                fixture.check("static source revisions refresh rendered pixels", !refracted.equals(refreshed));
                const source = refractiveSurface.refractionSource;
                refractiveSurface.refractionSource = null;
                const plain = grabImage(renderWindow.contentItem);
                refractiveSurface.refractionSource = source;
                fixture.check("application-owned source changes rendered pixels", !refracted.equals(plain));
            }
            refractiveSurface.refractionLive = true;
            fixture.check("animated viewer content can keep refraction live", refractiveSurface.refractionSourceLive);
            refractiveSurface.refractionLive = false;
            const capturePath = Quickshell.env("FJORD_GLASS_CAPTURE_PATH") || "";
            if (capturePath !== "")
                refracted.save(capturePath);
        }

        function cleanupTestCase() {
            if (fixture.failures === 0 && fixture.renderChecks === 1)
                fixture.log.info("FIXTURE PASS");
            else
                fixture.log.error(`FAIL rendered checks did not complete: ${fixture.renderChecks}`);
            Qt.callLater(Qt.quit);
        }
    }

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;

        check("Umbriel compositor blur is managed outside the client protocol", BlurService.compositorManaged);

        SettingsData.themeMode = "light";
        SettingsData.glassStrength = "subtle";
        SettingsData.performanceMode = false;
        check("light mode resolves", Theme.isLightMode);
        check("subtle material applies a tint", !Qt.colorEqual(surface.materialColor, surface.baseColor));
        check("subtle material keeps a quiet highlight", Theme.glassHighlightAlpha < 0.2);
        check("application-owned content enables refraction", refractiveSurface.refractionEnabled);
        check("refraction captures only the surface-sized source area", Math.abs(refractiveSurface.refractionSourceRect.width - refractiveSurface.width) < 1 && Math.abs(refractiveSurface.refractionSourceRect.height - refractiveSurface.height) < 1);
        check("refraction texture stays at half resolution", Math.abs(refractiveSurface.refractionTextureSize.width - refractiveSurface.width * 0.5) < 1);
        check("static viewer content uses on-demand refraction capture", !refractiveSurface.refractionSourceLive);

        SettingsData.glassStrength = "full";
        check("full strength updates the surface", surface.strength === 1 && Theme.glassHighlightAlpha > 0.3);

        SettingsData.themeMode = "dark";
        check("dark mode resolves", !Theme.isLightMode);
        check("dark mode lowers the specular highlight", Theme.glassHighlightAlpha < 0.3);

        SettingsData.performanceMode = true;
        check("performance mode disables glass highlights", surface.strength === 0 && surface.border.width === 0);
        check("performance mode disables refraction source capture", !refractiveSurface.refractionEnabled);
        check("performance mode disables optional animations", !Theme.animationsEnabled && Theme.springMotionDisabled && Theme.currentAnimationSpeed === DC.Style.AnimationSpeed.None);

        SettingsData.performanceMode = false;
        finish();
    }
}
