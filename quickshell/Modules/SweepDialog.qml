pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.FileBrowser

GlassDialog {
    id: root
    objectName: "sweepDialog"

    property var transport: DuxFilesService
    property bool busy: false
    property bool scanning: false
    property bool cancelling: false
    property string scanId: ""
    property bool reviewing: false
    property bool showingReport: false
    property int requestSerial: 0
    property var result: ({})
    property var selected: ({})
    property string scanPath: ""
    property string notice: ""
    property int idleDays: 0
    property double scanTime: 0
    readonly property var visibleCandidates: {
        const entries = result.candidates || [];
        if (reviewing || showingReport || idleDays === 0)
            return entries;
        const cutoff = scanTime - idleDays * 86400000;
        return entries.filter(item => typeof item.projectActiveMs === "number" && Number.isFinite(item.projectActiveMs) && item.projectActiveMs >= 0 && item.projectActiveMs <= cutoff);
    }
    readonly property var selectedIds: Object.keys(selected).filter(id => selected[id])
    readonly property var selectionEstimate: {
        const items = (result.candidates || []).filter(item => reviewing || selected[item.id]);
        return {"bytes": items.reduce((sum, item) => sum + Math.max(0, item.estimatedBytes || 0), 0), "partial": items.some(item => item.bytesKnown === false)};
    }

    title: reviewing ? I18n.tr("Review cleanup", "Sweep cleanup confirmation title") : I18n.tr("Sweep scan", "Sweep scan dialog title")
    maximumWidth: Theme.dialogMaxWidth
    supportingText: {
        if (busy && notice)
            return notice;
        if (busy)
            return cancelling ? I18n.tr("Cancelling…", "Sweep scan cancellation progress") : I18n.tr("Working…", "Sweep operation progress");
        if (notice)
            return notice;
        if (result.error)
            return result.error;
        if (!result.summary)
            return "";
        const skipped = result.summary.skippedDirs ? I18n.tr("%1 folders skipped", "Sweep scan incomplete directory count").arg(result.summary.skippedDirs) : "";
        const count = reviewing ? (result.candidates || []).length : selectedIds.length;
        const selectedCount = I18n.tr("%1 selected · estimated %2", "Sweep scan selection count and estimated size").arg(count).arg(FileFormat.size(selectionEstimate.bytes) + (selectionEstimate.partial ? "+" : ""));
        const filterNote = idleDays > 0 && !reviewing ? I18n.tr("Only projects with a known activity estimate are shown; other projects are excluded.", "Sweep inactivity filter explanation") : "";
        const status = reviewing ? I18n.tr("Sweep will move the listed items into a .sweep-trash folder inside the scan target. This is not the desktop trash and does not immediately free space. Sweep checks items again before moving them.", "Sweep permanent deletion warning") : I18n.tr("Select items to review. No files have been removed.", "Sweep selection notice");
        return [scanPath, selectedCount, skipped, filterNote, status].filter(Boolean).join("\n");
    }

    function scan(path) {
        scanPath = path;
        result = ({});
        selected = ({});
        notice = "";
        idleDays = 0;
        scanTime = Date.now();
        reviewing = false;
        showingReport = false;
        busy = true;
        scanning = true;
        cancelling = false;
        scanId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
        const serial = ++requestSerial;
        open();
        root.transport.call("sweep.scan", { "path": path, "scanId": scanId }, response => {
            if (serial !== root.requestSerial)
                return;
            root.result = response;
            root.busy = false;
            root.scanning = false;
            root.cancelling = false;
        });
    }
    function cancelScan() {
        if (!scanning || cancelling)
            return;
        notice = "";
        cancelling = true;
        root.transport.call("sweep.cancel", {"scanId": scanId}, response => {
            if (root.scanning && (!response.cancelled || response.error)) {
                root.cancelling = false;
                root.notice = response.error || I18n.tr("Scan has not started yet; try again.", "Sweep scan cancellation status");
            }
        });
    }
    function setIdleFilter(days) {
        idleDays = days;
        selected = ({});
    }
    function selectVisible() {
        const next = ({});
        for (const item of visibleCandidates) {
            if (item.riskTier === "safe" || item.riskTier === "caution")
                next[item.id] = true;
        }
        selected = next;
    }
    function activityLabel(item) {
        if (typeof item.projectActiveMs !== "number" || !Number.isFinite(item.projectActiveMs) || item.projectActiveMs < 0)
            return I18n.tr("Project activity unknown", "Sweep project activity unavailable");
        return I18n.tr("Last project activity: %1", "Sweep estimated last project activity").arg(Qt.formatDateTime(new Date(item.projectActiveMs), "yyyy-MM-dd HH:mm"));
    }
    function prepare() {
        busy = true;
        const serial = ++requestSerial;
        root.transport.call("sweep.prepare", { "token": result.token, "ids": selectedIds }, response => {
            if (serial !== root.requestSerial)
                return;
            root.busy = false;
            root.result = response;
            root.reviewing = !response.error;
        });
    }
    function apply() {
        busy = true;
        const serial = ++requestSerial;
        root.transport.call("sweep.apply", { "token": result.token, "confirmed": true }, response => {
            if (serial !== root.requestSerial)
                return;
            root.busy = false;
            root.reviewing = false;
            root.showingReport = true;
            const entries = [];
            if (response.trashMoves)
                response.trashMoves.forEach(item => entries.push({ "path": item.path + " → " + item.destination }));
            if (response.failedPaths)
                response.failedPaths.forEach(item => entries.push({ "path": item.path, "details": item.error }));
            root.result = { "candidates": entries };
            root.notice = response.error || I18n.tr("Moved: %1 · Failed: %2. The items remain in .sweep-trash; space has not been freed.", "Sweep cleanup result").arg(response.deletedCount).arg(response.failedCount);
            if (response.interrupted)
                root.notice += "\n" + I18n.tr("The operation was interrupted; scan again before retrying.", "Sweep interrupted result");
        });
    }
    onClosed: {
        requestSerial++;
        if (scanning && scanId)
            root.transport.call("sweep.cancel", {"scanId": scanId}, () => {});
        if (result.token)
            root.transport.call("sweep.discard", {"token": result.token}, () => {});
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS
        visible: !!root.result.token && !root.busy && !root.reviewing && !root.showingReport
        ComboBox {
            id: idleFilter
            objectName: "sweepIdleFilter"
            model: [
                I18n.tr("All projects", "Sweep project activity filter"),
                I18n.tr("No activity for 30 days", "Sweep project activity filter"),
                I18n.tr("No activity for 90 days", "Sweep project activity filter"),
                I18n.tr("No activity for 180 days", "Sweep project activity filter")
            ]
            currentIndex: [0, 30, 90, 180].indexOf(root.idleDays)
            onActivated: index => root.setIdleFilter([0, 30, 90, 180][index])
        }
        Button {
            text: I18n.tr("Select visible", "Sweep selection action")
            enabled: root.visibleCandidates.length > 0
            onClicked: root.selectVisible()
        }
        Button {
            text: I18n.tr("Clear selection", "Sweep selection action")
            enabled: root.selectedIds.length > 0
            onClicked: root.selected = ({})
        }
    }

    StyledText {
        width: parent.width
        visible: !!root.result.token && !root.busy && !root.reviewing && root.visibleCandidates.length === 0
        text: I18n.tr("No candidates match this filter", "Sweep project filter empty state")
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.Wrap
    }

    DListView {
        width: parent.width
        height: Math.min(contentHeight, root.height / 2)
        clip: true
        model: root.visibleCandidates
        delegate: Row {
            id: candidate
            required property var modelData
            width: ListView.view.width
            spacing: Theme.spacingXXS
            CheckBox {
                visible: !root.reviewing && !root.showingReport
                enabled: !root.busy && (candidate.modelData.riskTier === "safe" || candidate.modelData.riskTier === "caution")
                checked: !!root.selected[candidate.modelData.id]
                onToggled: {
                    const next = Object.assign({}, root.selected);
                    next[candidate.modelData.id] = checked;
                    root.selected = next;
                }
            }
            Column {
                width: candidate.width - (root.reviewing || root.showingReport ? 0 : 48)
                spacing: Theme.spacingXXS
                StyledText {
                    width: parent.width
                    text: candidate.modelData.path
                    textFormat: Text.PlainText
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WrapAnywhere
                }
                StyledText {
                    width: parent.width
                    visible: !root.showingReport
                    text: (candidate.modelData.projectRoot ? I18n.tr("Project: %1", "Sweep candidate project").arg(candidate.modelData.projectRoot) + " · " : "") + root.activityLabel(candidate.modelData)
                    textFormat: Text.PlainText
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WrapAnywhere
                }
                StyledText {
                    width: parent.width
                    visible: !!text
                    text: root.showingReport ? (candidate.modelData.details || "") : `${candidate.modelData.kind || ""} · ${candidate.modelData.riskTier} · ${FileFormat.size(candidate.modelData.estimatedBytes)}${candidate.modelData.bytesKnown === false ? "+" : ""} · ${(candidate.modelData.reasons || []).join(", ")}`
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }
            }
        }
    }
    actions: [
        TextButton {
            visible: root.scanning
            enabled: !root.cancelling
            text: I18n.tr("Cancel", "cancel a running Sweep scan")
            onClicked: root.cancelScan()
        },
        TextButton {
            text: I18n.tr("Close", "dialog button dismissing a dialog")
            enabled: !root.busy
            onClicked: root.close()
        },
        DButton {
            visible: !!root.result.token
            enabled: !root.busy && (root.reviewing || root.selectedIds.length > 0)
            text: root.reviewing ? I18n.tr("Move selected items", "confirm moving Sweep cleanup items") : I18n.tr("Review selection", "review Sweep cleanup selection")
            danger: root.reviewing
            onClicked: root.reviewing ? root.apply() : root.prepare()
        }
    ]
}
