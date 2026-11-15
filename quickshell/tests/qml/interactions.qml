pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.Common
import qs.Services
import qs.Modules
import qs.DCommon.Common as DC
import qs.DCommon.FileBrowser

ShellRoot {
    id: root

    readonly property var log: Log.scoped("fixture")

    property var window: null
    property bool ready: false
    property int openRequests: 0
    property int mountRequests: 0
    property var mountReply: null

    Component {
        id: mainWindow

        MainWindow {
            windowId: 1
        }
    }

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;
        DC.Host.files = DirectoryService;
        window = mainWindow.createObject(root);
        ready = true;
    }

    readonly property QtObject fakeTransport: QtObject {
        property bool connected: true
        function subscribeTopic(topic, callback) {
        }
        function unsubscribeTopic(topic, callback) {
        }
        function callReporting(method, params, failed, callback) {
            call(method, params, result => {
                if (result.error)
                    failed(result.error, result.code);
                callback?.(result);
            });
        }

        function call(method, params, callback) {
            sendRequest(method, params, response => callback?.(DuxFilesService.unwrap(response)));
        }
        function sendRequest(method, params, callback) {
            let result = {};
            switch (method) {
            case "files.open":
                root.openRequests++;
                break;
            case "devices.mount":
                root.mountRequests++;
                root.mountReply = callback;
                return;
            case "devices.list":
                result = {
                    available: true,
                    devices: [
                        {
                            id: "root",
                            name: "System SSD",
                            system: true,
                            hidden: false,
                            mounted: true,
                            mountPoint: "/",
                            mountPoints: ["/"],
                            device: "/dev/nvme0n1p2",
                            fstype: "ext4",
                            iconName: "drive-harddisk"
                        },
                        {
                            id: "home",
                            name: "Home",
                            system: false,
                            protected: true,
                            hidden: true,
                            mounted: true,
                            mountPoint: "/home",
                            mountPoints: ["/home"],
                            device: "/dev/nvme0n1p3",
                            iconName: "drive-harddisk"
                        },
                        {
                            id: "data",
                            name: "Projects",
                            system: false,
                            hidden: true,
                            mounted: true,
                            mountPoint: "/mnt/projects",
                            mountPoints: ["/mnt/projects", "/srv/projects"],
                            device: "/dev/nvme1n1p1",
                            fstype: "btrfs",
                            iconName: "drive-harddisk"
                        },
                        {
                            id: "usb",
                            name: "Backup",
                            system: false,
                            hidden: false,
                            mounted: false,
                            mountPoint: "",
                            mountPoints: [],
                            device: "/dev/sda1",
                            fstype: "ext4",
                            iconName: "drive-removable-media"
                        }
                    ]
                };
                break;
            case "devices.usage":
                result = {
                    usage: [
                        {
                            mountPoint: "/",
                            total: 1000000000000,
                            used: 250000000000,
                            free: 750000000000
                        },
                        {
                            mountPoint: "/mnt/projects",
                            total: 2000000000000,
                            used: 1200000000000,
                            free: 800000000000
                        },
                        {
                            mountPoint: "/srv/projects",
                            total: 2000000000000,
                            used: 1200000000000,
                            free: 800000000000
                        }
                    ]
                };
                break;
            case "network.mounts":
                result = {
                    available: true,
                    mounts: [
                        {
                            id: "nas",
                            name: "NAS",
                            path: "/run/user/1000/gvfs/nas",
                            kind: "network",
                            iconName: "folder-remote"
                        }
                    ]
                };
                break;
            }
            if (callback)
                callback({
                    result
                });
        }
    }

    readonly property QtObject fakeStorage: QtObject {
        property var reply: null
        property var projectsReply: null
        property var historyReply: null
        property string lastId: ""
        function call(method, params, callback) {
            if (method === "storage.scan") {
                lastId = params.scanId;
                reply = callback;
            } else if (method === "storage.projects") {
                lastId = params.scanId;
                projectsReply = callback;
            } else if (method === "storage.cancel") {
                callback({"cancelled": params.scanId === lastId});
            } else if (method === "sweep.history") {
                historyReply = callback;
            }
        }
    }

    readonly property QtObject fakeSweep: QtObject {
        property var reply: null
        property var prepareReply: null
        property var preparedIds: []
        property string lastId: ""
        function call(method, params, callback) {
            if (method === "sweep.scan") {
                lastId = params.scanId;
                reply = callback;
            } else if (method === "sweep.cancel") {
                if (params.scanId === lastId)
                    callback({"cancelled": true});
            } else if (method === "sweep.prepare") {
                preparedIds = params.ids;
                prepareReply = callback;
            } else {
                callback({});
            }
        }
    }

    SignalSpy {
        id: dragSpy
        signalName: "itemDragStarted"
    }

    TestCase {
        name: "Interactions"
        when: root.ready
        function check(actual, expected) {
            compare(actual, expected);
        }
        function entries(directory) {
            directory.entries.clear();
            directory.error = "";
            directory.loading = false;
            for (let i = 0; i < 60; i++)
                directory.entries.append({
                    name: "Document " + i + ".txt",
                    path: "/tmp/document" + i,
                    isDir: false,
                    isSymlink: false,
                    symlinkBroken: false,
                    size: 1024,
                    mtimeMs: 1000,
                    ctimeMs: 1000,
                    mode: "-rw-r--r--",
                    owner: "brandon",
                    group: "brandon",
                    iconName: "text-plain",
                    thumbnail: "",
                    mime: "text/plain",
                    extension: "txt",
                    displayName: "",
                    untrusted: false,
                    unreadable: false,
                    hidden: false
                });
        }
        function test_interactions() {
            const win = root.window;
            const surface = win.contentItem.children.find(child => child.isFloatingWindowSurface === true);
            SettingsData.animationDuration = 0;
            win.minimumSize = Qt.size(1100, 760);
            win.implicitWidth = 1100;
            win.implicitHeight = 760;
            CacheData.sidebarWidth = 240;
            DevicesService.transport = root.fakeTransport;
            NetworkService.transport = root.fakeTransport;
            tryCompare(surface, "width", 1100);
            AppsService.transport = root.fakeTransport;
            SettingsData.openInViewer = true;
            const picture = {"path": "/tmp/example.png", "name": "example.png", "mime": "image/png", "isDir": false};
            win.openFlow.viewerResolver = (path, callback) => callback({"mime": "image/png", "viewer": "image"});
            win.openFlow.activate(picture);
            check(win.tabManager.tabState(win.tabManager.currentTab).content.path, picture.path);
            const contentViewer = findChild(win, "contentViewer");
            verify(contentViewer !== null);
            tryCompare(contentViewer, "open", true);
            check(contentViewer.path, picture.path);
            win.tabManager.selectTab(0);
            tryCompare(contentViewer, "open", false);
            win.tabManager.selectTab(1);
            tryCompare(contentViewer, "open", true);
            check(root.openRequests, 0);
            win.tabManager.closeContentTab();
            win.toggleSplit();
            tryVerify(() => win.secondPane !== null);
            const firstPane = win.panes[0];
            const secondPane = win.secondPane;
            const firstPath = firstPane.path;
            secondPane.navigate("/tmp");
            tryCompare(secondPane, "path", "/tmp");
            compare(firstPane.path, firstPath, "navigating the second pane leaves the first pane unchanged");
            win.tabManager.captureTabs();
            compare(win.tabManager.tabState(win.tabManager.currentTab).panes[1].path, "/tmp", "the second pane path is saved in its tab");
            win.toggleSplit();
            tryVerify(() => win.secondPane === null);
            wait(50);
            win.toggleSplit();
            tryVerify(() => win.secondPane !== null);
            compare(win.secondPane.path, "/tmp", "reopening Split View restores the second pane path");
            win.toggleSplit();
            tryVerify(() => win.secondPane === null);
            SettingsData.openInViewer = false;
            win.openFlow.activate(picture);
            check(root.openRequests, 1);
            check(win.preview.open, false);
            SettingsData.openInViewer = true;
            win.preview.present(picture);
            tryCompare(win.preview, "open", true);
            mouseWheel(win.preview.imageStage, win.preview.imageStage.width * 0.75, win.preview.imageStage.height / 2, 0, 120);
            tryVerify(() => win.preview.zoom > 1);
            verify(win.preview.panX < 0);
            win.preview.dismiss();
            const pane = win.activePane;
            pane.navigate("/tmp");
            pane.setViewMode("grid");
            tryVerify(() => pane.body.view?.cellWidth > 0);
            entries(pane.body.directory);
            pane.body.directory.entries.setProperty(0, "mime", "image/png");
            pane.body.directory.entries.setProperty(2, "mime", "image/png");
            win.preview.present({"path": "/tmp/document0", "name": "first.png", "mime": "image/png"});
            win.openFlow.viewerResolver = (path, callback) => callback({"mime": "image/png", "viewer": "image"});
            win.openFlow.galleryStep(1, win.preview, false);
            compare(win.preview.path, "/tmp/document2");
            win.openFlow.galleryStep(-1, win.preview, false);
            compare(win.preview.path, "/tmp/document0");
            win.openFlow.galleryStep(-1, win.preview, false);
            compare(win.preview.path, "/tmp/document0", "gallery stops at the first directory entry");
            win.openFlow.galleryStep(1, win.preview, false);
            compare(win.preview.path, "/tmp/document2", "gallery skips non-image files");
            win.preview.dismiss();
            pane.body.directory.entries.setProperty(0, "mime", "text/plain");
            pane.body.directory.entries.setProperty(2, "mime", "text/plain");
            win.openFlow.viewerResolver = (path, callback) => callback({"mime": pane.body.directory.entries.get(0).mime, "viewer": pane.body.directory.entries.get(0).mime === "application/pdf" ? "pdf" : "media"});
            win.previewOpen = true;
            pane.body.directory.entries.setProperty(0, "mime", "application/pdf");
            pane.selection.select("/tmp/document0");
            const sidePdf = findChild(win, "sidePdfLoader");
            verify(sidePdf !== null);
            tryCompare(sidePdf, "active", true);
            tryVerify(() => sidePdf.item !== null);
            win.preview.present({"path": "/tmp/example.png", "name": "example.png", "mime": "image/png"});
            tryCompare(sidePdf, "active", false);
            win.preview.dismiss();
            tryCompare(sidePdf, "active", true);
            pane.selection.clear();
            tryCompare(sidePdf, "active", false);
            let oldReply = null;
            win.openFlow.viewerResolver = (path, callback) => { oldReply = callback; };
            pane.selection.select("/tmp/document0");
            tryVerify(() => oldReply !== null);
            pane.selection.clear();
            pane.selection.select("/tmp/document0");
            oldReply({"mime": "application/pdf", "viewer": "pdf"});
            compare(sidePdf.active, false);
            pane.selection.clear();
            win.openFlow.viewerResolver = (path, callback) => callback({"mime": "text/plain", "viewer": "text"});
            pane.selection.select("/tmp/document0");
            wait(250);
            compare(sidePdf.active, false);
            pane.selection.clear();
            win.openFlow.viewerResolver = (path, callback) => callback({"mime": pane.body.directory.entries.get(0).mime, "viewer": "media"});
            pane.body.directory.entries.setProperty(0, "mime", "audio/wav");
            pane.selection.select("/tmp/document0");
            const sideMedia = findChild(win, "sideMediaLoader");
            verify(sideMedia !== null);
            tryCompare(sideMedia, "active", true);
            tryVerify(() => sideMedia.item !== null);
            compare(sideMedia.item.player.playbackState, 0);
            pane.selection.clear();
            pane.body.directory.entries.setProperty(0, "mime", "video/mp4");
            win.openFlow.viewerResolver = (path, callback) => callback({"mime": "video/mp4", "viewer": "media"});
            pane.selection.select("/tmp/document0");
            tryCompare(sideMedia, "active", true);
            tryVerify(() => sideMedia.item?.video === true);
            win.preview.present({"path": "/tmp/example.png", "name": "example.png", "mime": "image/png"});
            tryCompare(sideMedia, "active", false);
            win.preview.dismiss();
            tryCompare(sideMedia, "active", true);
            pane.selection.clear();
            tryCompare(sideMedia, "active", false);
            compare(sideMedia.item, null);
            pane.body.directory.entries.setProperty(0, "mime", "text/plain");
            win.openFlow.viewerResolver = (path, callback) => callback({"mime": "image/png", "viewer": "image"});
            let view = pane.body.view;
            tryVerify(() => view.itemAtIndex(0) !== null);
            dragSpy.target = view;
            view.positionViewAtBeginning();
            const tile = view.itemAtIndex(0);
            const blankY = FileBrowserMetrics.gridTileVerticalPadding / 2;
            check(tile.containsContent(tile.width / 2, blankY), false);
            mousePress(tile, tile.width / 2, blankY);
            mouseMove(view, view.cellWidth * 2 - 2, view.cellHeight - 2);
            tryVerify(() => pane.selection.paths.includes("/tmp/document0"));
            tryCompare(pane.selection.paths, "length", 2);
            mouseRelease(view, view.cellWidth * 2 - 2, view.cellHeight - 2);
            check(dragSpy.count, 0);
            check(pane.selection.paths.length, 2);
            const visual = tile.hitTargets[0];
            mouseClick(visual, visual.width / 2, visual.height / 2);
            check(pane.selection.paths, ["/tmp/document0"]);
            win.actions.runAction("previewExpand");
            compare(win.preview.open, true);
            compare(win.preview.kind, "image");
            win.preview.dismiss();
            mousePress(visual, visual.width / 2, visual.height / 2);
            mouseMove(visual, visual.width / 2 + 40, visual.height / 2);
            mouseRelease(visual, visual.width / 2 + 40, visual.height / 2);
            check(dragSpy.count, 1);
            DragService.end();
            pane.selection.select("/tmp/document10");
            mousePress(tile, tile.width / 2, blankY, Qt.LeftButton, Qt.ControlModifier);
            mouseMove(view, view.cellWidth * 2 - 2, view.cellHeight - 2);
            mouseRelease(view, view.cellWidth * 2 - 2, view.cellHeight - 2, Qt.LeftButton, Qt.ControlModifier);
            check(pane.selection.paths.includes("/tmp/document10"), true);
            check(pane.selection.paths.includes("/tmp/document1"), true);
            check(view.indicesIn(Qt.rect(view.cellWidth - FileBrowserMetrics.gridGap + 1, 20, FileBrowserMetrics.gridGap - 2, 20)).length, 0);
            SettingsData.language = "ar";
            tryVerify(() => view.itemAtIndex(0).x > view.width / 2);
            const firstTile = view.itemAtIndex(0);
            check(view.indicesIn(Qt.rect(firstTile.x + 1, firstTile.y + 1, 10, 10)), [0]);
            SettingsData.language = "en";
            tryVerify(() => view.itemAtIndex(0).x < view.width / 2);
            const before = view.contentY;
            mouseWheel(surface, surface.width - 4, 200, 0, -120);
            tryVerify(() => view.contentY > before);
            view.positionViewAtBeginning();
            mousePress(view, view.cellWidth - 2, view.cellHeight - 2);
            mouseMove(view, view.cellWidth - 2, view.height - 2);
            tryVerify(() => view.contentY > view.originY);
            mouseRelease(view, view.cellWidth - 2, view.height - 2);
            pane.setViewMode("list");
            tryVerify(() => pane.body.view !== view && pane.body.view?.itemAtIndex(0) !== null);
            view = pane.body.view;
            dragSpy.target = view;
            dragSpy.clear();
            view.positionViewAtBeginning();
            const row = view.itemAtIndex(0);
            const name = row.hitTargets[1];
            const blankX = name.x + name.contentWidth + Theme.spacingL;
            check(row.containsContent(blankX, row.height / 2), false);
            mousePress(row, blankX, row.height / 2);
            mouseMove(view, view.width - 80, view.rowPitch * 4);
            tryVerify(() => pane.selection.paths.length > 1);
            mouseRelease(view, view.width - 80, view.rowPitch * 4);
            check(dragSpy.count, 0);
            mouseClick(row, blankX, row.height / 2);
            check(pane.selection.paths, ["/tmp/document0"]);
            pane.body.directory.entries.setProperty(0, "isDir", true);
            view.chevrons = true;
            tryVerify(() => row.hitTargets[2].width > 0);
            const chevron = row.hitTargets[2];
            pane.selection.clear();
            mouseClick(chevron, chevron.width / 2, chevron.height / 2);
            check(pane.selection.paths, ["/tmp/document0"]);
            view.chevrons = false;
            pane.body.directory.entries.setProperty(0, "isDir", false);
            view.positionViewAtBeginning();
            mouseWheel(surface, surface.width - 4, 200, 0, -120);
            tryVerify(() => view.contentY > view.originY);
            function sidebarIn(item) {
                if (item instanceof Sidebar && item.visible)
                    return item;
                for (const child of item.children) {
                    const found = sidebarIn(child);
                    if (found)
                        return found;
                }
                return null;
            }
            const sidebar = sidebarIn(surface);
            verify(sidebar !== null);
            const rows = sidebar.rows();
            const system = rows.find(item => item.label === "/");
            const projects = rows.find(item => item.label === "/mnt/projects");
            verify(system !== undefined);
            verify(projects !== undefined);
            check(system.subtitle, "/dev/nvme0n1p2");
            check(projects.subtitle, "/dev/nvme1n1p1");
            check(system.actionIcon, "");
            const home = rows.find(item => item.label === "/home");
            verify(home !== undefined);
            check(home.actionIcon, "");
            check(home.actionTooltip, "");
            check(projects.actionTooltip, "Unmount");
            check(system.ringValue, 0.25);
            check(projects.ringValue, 0.6);
            verify(system.tooltipText.includes("/dev/nvme0n1p2"));
            verify(projects.tooltipText.includes("/mnt/projects"));
            projects.clicked();
            check(pane.path, "/mnt/projects");
            const backup = rows.find(item => item.label === "Backup");
            check(backup.actionTooltip, "Mount");
            backup.clicked();
            backup.clicked();
            check(root.mountRequests, 1);
            root.mountReply({
                error: "cancelled",
                code: "CANCELLED"
            });
            pane.restoreState({
                path: "computer:",
                back: ["/tmp", "computer:"]
            });
            check(pane.path, "/");
            pane.back();
            check(pane.path, "/");
            function jobsButtonIn(item) {
                if (item instanceof JobsButton)
                    return item;
                for (const child of item.children) {
                    const found = jobsButtonIn(child);
                    if (found)
                        return found;
                }
                return null;
            }
            const topbarJobs = jobsButtonIn(win.topbar);
            verify(topbarJobs !== null);
            DC.Host.ownWindowDecorations = false;
            tryCompare(win, "headerHostsJobs", false);
            const topbarY = win.topbar.mapToItem(surface, 0, 0).y;
            FileOpsService.jobs = [
                {
                    id: "j1",
                    state: "running"
                }
            ];
            tryCompare(topbarJobs, "visible", true);
            check(win.topbar.mapToItem(surface, 0, 0).y, topbarY);
            DC.Host.ownWindowDecorations = true;
            tryCompare(topbarJobs, "visible", false);
            FileOpsService.jobs = [];
            const storage = findChild(win, "storageDialog");
            verify(storage !== null);
            storage.show("/tmp");
            tryVerify(() => storage.mounts.some(item => item.mountPoint === "/" && item.total > 0));
            compare(win.dialogs.anyOpen, true);
            storage.transport = root.fakeStorage;
            storage.analyze();
            check(storage.scanning, true);
            root.fakeStorage.reply({"visited": 2, "skipped": 1, "truncated": false, "totalSize": 17, "directories": [{"path": "/tmp/folder", "size": 12}], "files": [{"path": "/tmp/file", "size": 5}]});
            check(storage.scanning, false);
            check(storage.analysisRows.length, 2);
            verify(storage.supportingText.indexOf("17 B") >= 0);
            verify(storage.supportingText.indexOf("incomplete") >= 0);
            storage.analyze();
            storage.cancelScan();
            check(storage.cancelling, true);
            root.fakeStorage.reply({"error": "cancelled"});
            check(storage.scanning, false);
            storage.scanProjects();
            check(storage.scanning, true);
            check(storage.projectsMode, true);
            root.fakeStorage.projectsReply({"visited": 7, "skipped": 0, "projects": [{"path": "/tmp/project", "name": "project", "kinds": ["Go"], "size": 2048, "lastActivityMs": 1760000000000}]});
            check(storage.scanning, false);
            check(storage.projectResult.projects.length, 1);
            verify(storage.supportingText.indexOf("Activity is estimated") >= 0);
            storage.hideProjects();
            check(storage.projectResult, null);
            storage.showHistory();
            check(storage.historyLoading, true);
            const oldHistoryReply = root.fakeStorage.historyReply;
            storage.hideHistory();
            storage.showHistory();
            oldHistoryReply({"recent": []});
            check(storage.historyLoading, true);
            root.fakeStorage.historyReply({"recent": [{"ts": "2026-11-15", "targetDir": "/tmp", "deleted": 1, "bytesFreed": 42, "failed": 0, "trashDir": "/tmp/.sweep-trash"}]});
            check(storage.historyLoading, false);
            check(storage.historyEntries[0].trashDir, "/tmp/.sweep-trash");
            verify(storage.supportingText.indexOf("estimates") >= 0);
            storage.hideHistory();
            storage.close();
            const sweep = findChild(win, "sweepDialog");
            verify(sweep !== null);
            sweep.transport = root.fakeSweep;
            sweep.scan("/tmp");
            check(sweep.scanning, true);
            check(sweep.scanId !== "", true);
            sweep.cancelScan();
            check(sweep.cancelling, true);
            root.fakeSweep.reply({"error": "cancelled"});
            check(sweep.scanning, false);
            check(sweep.busy, false);
            sweep.scan("/tmp");
            root.fakeSweep.reply({"token": "fixture", "summary": {"skippedDirs": 0}, "candidates": [
                {"id": "old", "path": "/tmp/old", "riskTier": "safe", "estimatedBytes": 5, "projectActiveMs": sweep.scanTime - 100 * 86400000},
                {"id": "new", "path": "/tmp/new", "riskTier": "caution", "estimatedBytes": 4, "projectActiveMs": sweep.scanTime - 86400000},
                {"id": "danger", "path": "/tmp/danger", "riskTier": "dangerous", "estimatedBytes": 3, "projectActiveMs": sweep.scanTime - 100 * 86400000},
                {"id": "unknown", "path": "/tmp/unknown", "riskTier": "safe", "estimatedBytes": 2}
            ]});
            sweep.setIdleFilter(90);
            check(sweep.visibleCandidates.length, 2);
            sweep.selectVisible();
            check(sweep.selectedIds, ["old"]);
            sweep.setIdleFilter(0);
            check(sweep.selectedIds.length, 0);
            sweep.selectVisible();
            check(sweep.selectedIds.sort(), ["new", "old", "unknown"]);
            check(sweep.activityLabel({}), "Project activity unknown");
            sweep.prepare();
            check(root.fakeSweep.preparedIds.sort(), ["new", "old", "unknown"]);
            root.fakeSweep.prepareReply({"token": "prepared", "summary": {"skippedDirs": 0}, "candidates": [
                {"id": "old", "path": "/tmp/old", "riskTier": "safe", "estimatedBytes": 5},
                {"id": "new", "path": "/tmp/new", "riskTier": "caution", "estimatedBytes": 4},
                {"id": "unknown", "path": "/tmp/unknown", "riskTier": "safe", "estimatedBytes": 2}
            ]});
            check(sweep.reviewing, true);
            check(sweep.visibleCandidates.length, 3);
            sweep.close();
            root.log.info("FIXTURE PASS");
        }
    }
}
