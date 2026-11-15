pragma ComponentBehavior: Bound
//@ pragma AppId io.github.febsho.fjordfiles

import QtQuick
import QtQuick.Window
import Quickshell
import qs.Common
import qs.Modules
import qs.Services
import qs.DCommon.Common as DC

ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("FJORD_GLASS_MODE") || "plain"
    readonly property bool glassEnabled: root.mode === "glass"
    readonly property bool refractiveEnabled: root.mode === "refraction"
    readonly property string requestedTheme: Quickshell.env("FJORD_GLASS_THEME") ?? ""
    readonly property real warmupSeconds: Number(Quickshell.env("FJORD_GLASS_WARMUP") || 2)
    readonly property real measureSeconds: Number(Quickshell.env("FJORD_GLASS_SECONDS") || 8)
    property int measuredFrames: 0
    property bool finished: false
    property bool setupComplete: false

    function finishBenchmark() {
        if (finished)
            return;
        finished = true;
        frameAnimation.running = false;
        Log.info("FJORD_GLASS_BENCHMARK", {
            "mode": root.mode,
            "frames": measuredFrames,
            "seconds": measureSeconds,
            "fps": measuredFrames / measureSeconds,
            "compositorBlurProtocol": BlurService.probed ? BlurService.available : null
        });
        Qt.quit();
    }

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        if (requestedTheme === "light" || requestedTheme === "dark")
            SettingsData.themeMode = requestedTheme;
        BlurService.probe();
        setupComplete = true;
    }

    Component {
        id: plainTile

        Rectangle {
            radius: Theme.cornerRadiusM
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.floatingWindowForegroundAlpha * 0.72)
            border.width: 1
            border.color: Theme.withAlpha(Theme.surfaceText, 0.06)
            Text {
                anchors.centerIn: parent
                text: "Folder"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    Component {
        id: glassTile

        GlassSurface {
            topLeftRadius: Theme.cornerRadiusM
            topRightRadius: Theme.cornerRadiusM
            bottomLeftRadius: Theme.cornerRadiusM
            bottomRightRadius: Theme.cornerRadiusM
            baseColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.floatingWindowForegroundAlpha * 0.72)
            Text {
                anchors.centerIn: parent
                text: "Folder"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    Window {
        id: benchmarkWindow

        width: 1280
        height: 800
        visible: root.setupComplete
        color: Theme.surface
        title: "Fjord Files glass " + (root.requestedTheme || "theme")

        Rectangle {
            id: benchmarkBackdrop

            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.primaryContainer }
                GradientStop { position: 1; color: Theme.tertiaryContainer }
            }
        }

        Grid {
            anchors.centerIn: parent
            columns: 10
            spacing: Theme.spacingM
            visible: !root.refractiveEnabled

            Repeater {
                model: 100

                Loader {
                    required property int index
                    width: 112
                    height: 62
                    sourceComponent: root.glassEnabled ? glassTile : plainTile
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Theme.spacingL
            text: root.refractiveEnabled ? "Application-owned refraction" : root.glassEnabled ? "Glass material" : "Plain surfaces"
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
        }

        GlassSurface {
            visible: root.refractiveEnabled
            width: 560
            height: 64
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingXL
            baseColor: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.floatingWindowForegroundAlpha * 0.55)
            topLeftRadius: Theme.cornerRadiusL
            topRightRadius: Theme.cornerRadiusL
            bottomLeftRadius: Theme.cornerRadiusL
            bottomRightRadius: Theme.cornerRadiusL
            refractionSource: benchmarkBackdrop

            Text {
                anchors.centerIn: parent
                text: "Playback controls · 00:32 / 02:14"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    FrameAnimation {
        id: frameAnimation
        running: benchmarkWindow.visible

        onTriggered: {
            if (elapsedTime >= root.warmupSeconds && elapsedTime < root.warmupSeconds + root.measureSeconds)
                root.measuredFrames++;
            if (elapsedTime < root.warmupSeconds + root.measureSeconds)
                return;
            root.finishBenchmark();
        }
    }

    Timer {
        running: true
        interval: Math.ceil((root.warmupSeconds + root.measureSeconds + 10) * 1000)
        onTriggered: root.finishBenchmark()
    }
}
