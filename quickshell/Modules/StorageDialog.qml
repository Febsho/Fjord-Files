pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.FileBrowser

OverlayDialog {
    id: root
    objectName: "storageDialog"

    property string currentPath: ""
    property var transport: DuxFilesService
    property var analysis: null
    property string analysisError: ""
    property bool projectsMode: false
    property var projectResult: null
    property string projectError: ""
    property int projectSerial: 0
    property bool scanning: false
    property bool cancelling: false
    property string scanId: ""
    property int requestSerial: 0
    property int historySerial: 0
    property bool historyMode: false
    property bool historyLoading: false
    property string historyError: ""
    property var historyEntries: []
    readonly property var analysisRows: {
        if (!analysis)
            return [];
        const folders = (analysis.directories || []).map(item => ({"path": item.path, "size": item.size, "folder": true}));
        const files = (analysis.files || []).map(item => ({"path": item.path, "size": item.size, "folder": false}));
        return folders.concat(files);
    }
    readonly property var mounts: Object.values(DevicesService.usage).filter(item => item.total > 0).sort((a, b) => a.mountPoint.localeCompare(b.mountPoint))
    signal scanRequested(string path)

    title: I18n.tr("Storage", "storage usage overview")
    maximumWidth: Theme.dialogMaxWidth
    supportingText: {
        if (historyMode) {
            if (historyLoading)
                return I18n.tr("Loading…", "Sweep history progress");
            if (historyError)
                return historyError;
            return historyEntries.length ? I18n.tr("Recent Sweep sessions; sizes are estimates.", "Sweep history explanation") : I18n.tr("No recent Sweep sessions", "Sweep history empty state");
        }
        if (projectsMode) {
            if (scanning)
                return cancelling ? I18n.tr("Cancelling…", "project scan progress") : I18n.tr("Finding projects…", "project scan progress");
            if (projectError)
                return projectError;
            if (projectResult) {
                const status = projectResult.truncated || projectResult.projectsTruncated || projectResult.skipped ? I18n.tr("Results may be incomplete", "project scan partial result") : I18n.tr("Project scan complete", "project scan result");
                return status + " · " + I18n.tr("%1 projects · %2 entries · %3 skipped", "project scan result counts").arg((projectResult.projects || []).length).arg(projectResult.visited).arg(projectResult.skipped) + "\n" + I18n.tr("Activity is estimated from project-file modification times. Common generated folders are excluded from activity, but included in size.", "project inventory explanation");
            }
            return I18n.tr("Read-only inventory of projects in this folder. Project sizes can overlap for nested projects.", "project inventory introduction");
        }
        if (scanning && analysisError)
            return analysisError;
        if (scanning)
            return cancelling ? I18n.tr("Cancelling…", "storage scan progress") : I18n.tr("Analyzing folder…", "storage scan progress");
        if (analysisError)
            return analysisError;
        if (analysis) {
            const status = analysis.truncated || analysis.skipped ? I18n.tr("Results may be incomplete", "storage scan partial result") : I18n.tr("Analysis complete", "storage scan result");
            return status + " · " + I18n.tr("%1 entries · %2 skipped", "storage scan result counts").arg(analysis.visited).arg(analysis.skipped) + "\n" + I18n.tr("Scanned logical size: %1. Bars show each item's share; files can be inside listed folders. Hard links are counted once.", "storage scan explanation").arg(FileFormat.size(analysis.totalSize || 0));
        }
        return mounts.length ? I18n.tr("Usage of mounted filesystems", "storage usage overview") : I18n.tr("No filesystem usage data is available", "storage usage overview empty state");
    }

    function show(path) {
        currentPath = path;
        analysis = null;
        analysisError = "";
        projectSerial++;
        projectsMode = false;
        projectResult = null;
        projectError = "";
        historyMode = false;
        historyLoading = false;
        historyError = "";
        DevicesService.refreshUsage(true);
        open();
    }

    function showHistory() {
        if (scanning || historyLoading)
            return;
        historyMode = true;
        historyLoading = true;
        historyError = "";
        historyEntries = [];
        const serial = ++historySerial;
        transport.call("sweep.history", null, response => {
            if (serial !== root.historySerial)
                return;
            root.historyLoading = false;
            if (response.error)
                root.historyError = response.error;
            else
                root.historyEntries = (response.recent || []).slice().reverse();
        });
    }
    function hideHistory() {
        historySerial++;
        historyMode = false;
        historyLoading = false;
        historyError = "";
    }

    function analyze() {
        if (scanning || !currentPath.startsWith("/"))
            return;
        analysis = null;
        analysisError = "";
        scanning = true;
        cancelling = false;
        scanId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
        const serial = ++requestSerial;
        transport.call("storage.scan", {"path": currentPath, "scanId": scanId}, response => {
            if (serial !== root.requestSerial)
                return;
            root.scanning = false;
            root.cancelling = false;
            if (response.error)
                root.analysisError = response.error;
            else
                root.analysis = response;
        });
    }
    function scanProjects() {
        if (scanning || !currentPath.startsWith("/"))
            return;
        projectResult = null;
        projectError = "";
        projectsMode = true;
        scanning = true;
        cancelling = false;
        scanId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
        const serial = ++projectSerial;
        transport.call("storage.projects", {"path": currentPath, "scanId": scanId}, response => {
            if (serial !== root.projectSerial)
                return;
            root.scanning = false;
            root.cancelling = false;
            if (response.error)
                root.projectError = response.error;
            else
                root.projectResult = response;
        });
    }
    function hideProjects() {
        projectSerial++;
        projectsMode = false;
        projectResult = null;
        projectError = "";
    }
    function cancelScan() {
        if (!scanning || cancelling)
            return;
        analysisError = "";
        cancelling = true;
        transport.call("storage.cancel", {"scanId": scanId}, response => {
            if (root.scanning && (!response.cancelled || response.error)) {
                root.cancelling = false;
                root.analysisError = response.error || I18n.tr("Scan has not started yet; try again.", "storage scan cancellation status");
            }
        });
    }
    onClosed: {
        requestSerial++;
        historySerial++;
        projectSerial++;
        historyLoading = false;
        if (scanning)
            transport.call("storage.cancel", {"scanId": scanId}, () => {});
        scanning = false;
    }

    DListView {
        visible: !root.analysis && !root.historyMode && !root.projectsMode
        width: parent.width
        height: Math.min(contentHeight, root.height / 2)
        clip: true
        model: root.mounts
        delegate: Column {
            id: row
            required property var modelData
            width: ListView.view.width
            spacing: Theme.spacingXS
            StyledText {
                width: parent.width
                text: row.modelData.mountPoint
                color: Theme.surfaceText
                elide: Text.ElideMiddle
            }
            ProgressBar {
                width: parent.width
                from: 0
                to: 1
                value: Math.max(0, Math.min(1, row.modelData.used / row.modelData.total))
                Accessible.name: row.modelData.mountPoint
            }
            StyledText {
                width: parent.width
                text: I18n.tr("%1 used of %2", "storage usage summary").arg(FileFormat.size(row.modelData.used)).arg(FileFormat.size(row.modelData.total))
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
    DListView {
        visible: root.projectsMode && !!root.projectResult && !root.historyMode
        width: parent.width
        height: Math.min(contentHeight, root.height / 2)
        clip: true
        model: root.projectResult ? root.projectResult.projects || [] : []
        delegate: Column {
            id: projectRow
            required property var modelData
            width: ListView.view.width
            spacing: Theme.spacingXS
            StyledText {
                width: parent.width
                text: projectRow.modelData.name
                textFormat: Text.PlainText
                color: Theme.surfaceText
                elide: Text.ElideMiddle
            }
            StyledText {
                width: parent.width
                text: projectRow.modelData.path
                textFormat: Text.PlainText
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideMiddle
            }
            StyledText {
                width: parent.width
                text: (projectRow.modelData.kinds || []).join(" · ") + " · " + FileFormat.size(projectRow.modelData.size) + (projectRow.modelData.lastActivityMs ? " · " + I18n.tr("Last project-file change (estimate): %1", "estimated project activity").arg(new Date(projectRow.modelData.lastActivityMs).toLocaleString()) : " · " + I18n.tr("Activity unknown", "unknown project activity"))
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
    DListView {
        visible: !!root.analysis && !root.historyMode && !root.projectsMode
        width: parent.width
        height: Math.min(contentHeight, root.height / 2)
        clip: true
        model: root.analysisRows
        delegate: Column {
            id: itemRow
            required property var modelData
            width: ListView.view.width
            spacing: Theme.spacingXS
            StyledText {
                width: parent.width
                text: itemRow.modelData.path
                color: Theme.surfaceText
                elide: Text.ElideMiddle
            }
            StyledText {
                width: parent.width
                text: (itemRow.modelData.folder ? I18n.tr("Folder", "storage scan item") : I18n.tr("File", "storage scan item")) + " · " + FileFormat.size(itemRow.modelData.size) + (root.analysis.totalSize > 0 ? " · " + (100 * itemRow.modelData.size / root.analysis.totalSize).toFixed(1) + "%" : "")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
            ProgressBar {
                objectName: "storageShare"
                width: parent.width
                from: 0
                to: 1
                value: root.analysis.totalSize > 0 ? Math.max(0, Math.min(1, itemRow.modelData.size / root.analysis.totalSize)) : 0
                Accessible.name: I18n.tr("Share of scanned size", "storage scan bar") + ": " + itemRow.modelData.path
            }
        }
    }
    DListView {
        visible: root.historyMode
        width: parent.width
        height: Math.min(contentHeight, root.height / 2)
        clip: true
        model: root.historyEntries
        delegate: Column {
            id: historyRow
            required property var modelData
            width: ListView.view.width
            spacing: Theme.spacingXS
            StyledText {
                width: parent.width
                text: historyRow.modelData.ts + " · " + historyRow.modelData.targetDir
                textFormat: Text.PlainText
                color: Theme.surfaceText
                elide: Text.ElideMiddle
            }
            StyledText {
                width: parent.width
                text: (historyRow.modelData.trashDir ? I18n.tr("Moved to Sweep trash", "Sweep history session") : I18n.tr("Removed", "Sweep history session")) + " · " + I18n.tr("%1 items · %2 failed", "Sweep history item counts").arg(historyRow.modelData.deleted).arg(historyRow.modelData.failed) + " · " + I18n.tr("Estimated size: %1", "Sweep history estimated size").arg(FileFormat.size(historyRow.modelData.bytesFreed)) + (historyRow.modelData.interrupted ? " · " + I18n.tr("Interrupted", "Sweep history session") : "")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
            StyledText {
                width: parent.width
                visible: !!historyRow.modelData.trashDir
                text: historyRow.modelData.trashDir || ""
                textFormat: Text.PlainText
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideMiddle
            }
        }
    }
    StyledText {
        visible: root.projectsMode && !!root.projectResult && !(root.projectResult.projects || []).length && !root.scanning
        width: parent.width
        text: I18n.tr("No project folders found", "project inventory empty state")
        color: Theme.surfaceVariantText
        horizontalAlignment: Text.AlignHCenter
    }
    actions: [
        TextButton {
            visible: root.historyMode
            text: I18n.tr("Back", "return to storage overview")
            onClicked: root.hideHistory()
        },
        TextButton {
            visible: !root.historyMode && !root.projectsMode && !root.analysis && !root.scanning
            text: I18n.tr("Sweep history", "open Sweep cleanup history")
            onClicked: root.showHistory()
        },
        TextButton {
            visible: root.scanning && !root.historyMode
            enabled: !root.cancelling
            text: I18n.tr("Cancel", "cancel storage scan")
            onClicked: root.cancelScan()
        },
        TextButton {
            visible: !!root.analysis && !root.scanning && !root.historyMode && !root.projectsMode
            text: I18n.tr("Back", "return to storage overview")
            onClicked: root.analysis = null
        },
        TextButton {
            visible: root.projectsMode && !root.scanning && !root.historyMode
            text: I18n.tr("Back", "return to storage overview")
            onClicked: root.hideProjects()
        },
        DButton {
            visible: !root.projectsMode && !root.analysis && !root.scanning && !root.historyMode
            enabled: !root.scanning && root.currentPath.startsWith("/")
            text: I18n.tr("List projects", "storage project inventory action")
            onClicked: root.scanProjects()
        },
        DButton {
            visible: !root.projectsMode && !root.analysis && !root.scanning && !root.historyMode
            enabled: !root.scanning && root.currentPath.startsWith("/")
            text: I18n.tr("Analyze current folder", "storage scan action")
            onClicked: root.analyze()
        },
        TextButton {
            text: I18n.tr("Close", "dialog button dismissing a dialog")
            enabled: !root.scanning
            onClicked: root.close()
        },
        DButton {
            text: I18n.tr("Scan current folder with Sweep", "storage overview action")
            visible: !root.historyMode && !root.projectsMode
            enabled: !root.scanning && root.currentPath.startsWith("/")
            onClicked: {
                const path = root.currentPath;
                root.close();
                root.scanRequested(path);
            }
        }
    ]
}
