pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("BlurService")

    property bool available: false
    property bool probed: false

    readonly property bool requested: SettingsData.blurEnabled
    readonly property real radius: SettingsData.blurRadius
    readonly property bool supported: available || compositorManaged
    readonly property bool enabled: supported && requested && !SettingsData.performanceMode
    readonly property bool compositorManaged: {
        const desktops = (Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").toLowerCase().split(":");
        return desktops.includes("umbriel");
    }
    property bool applyInFlight: false
    property bool applyPending: false

    function scheduleUmbrielApply() {
        if (!compositorManaged)
            return;
        applyPending = true;
        applyTimer.restart();
    }

    function applyUmbriel() {
        if (!compositorManaged || !applyPending || applyInFlight)
            return;
        applyPending = false;
        applyInFlight = true;
        DuxFilesService.callReporting("system.blur.configure", {
            "enabled": requested,
            "radius": Math.round(radius)
        }, (message, code) => {
            root.log.warn(`Umbriel blur update failed (${code}): ${message}`);
            ToastService.info(message);
        }, () => {
            applyInFlight = false;
            if (applyPending)
                applyTimer.restart();
        });
    }

    onRequestedChanged: {
        if (compositorManaged) {
            scheduleUmbrielApply();
            return;
        }
        if (requested)
            probe();
    }
    onRadiusChanged: {
        if (requested)
            scheduleUmbrielApply();
    }

    Component.onCompleted: {
        if (compositorManaged)
            scheduleUmbrielApply();
        if (requested)
            probe();
    }

    Timer {
        id: applyTimer

        interval: 250
        repeat: false
        onTriggered: root.applyUmbriel()
    }

    function probe() {
        if (probed || probeProcess.running)
            return;
        probeProcess.running = true;
    }

    function applyVerdict(text) {
        available = text.trim() === "supported";
        probed = true;
    }

    Process {
        id: probeProcess

        command: ["dfiles", "blur", "check"]

        stdout: StdioCollector {
            onStreamFinished: root.applyVerdict(text)
        }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            root.log.warn(`blur probe exited with ${exitCode}`);
            root.applyVerdict("");
        }
    }
}
