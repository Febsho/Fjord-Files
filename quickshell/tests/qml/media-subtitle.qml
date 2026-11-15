pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Common
import qs.Modules
import qs.DCommon.Common as DC

ShellRoot {
    id: fixture
    property bool ready: false
    property bool passed: false
    Window {
        id: surface
        width: 800; height: 600; visible: true
        PreviewMedia { id: media; anchors.fill: parent; source: Qt.resolvedUrl("preview-tracks.mkv"); video: true; autoPlay: false }
    }
    function findItem(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const found = findItem(child, name);
            if (found) return found;
        }
        return null;
    }
    Component.onCompleted: { DC.Style.theme = Theme; DC.I18n.backend = I18n; ready = true; }
    TestCase {
        name: "MediaSubtitle"
        when: fixture.ready && surface.visible
        function test_subtitle() {
            tryVerify(() => media.player.subtitleTracks.length === 1 && media.player.duration > 0);
            media.audioOutput.volume = 0;
            media.player.activeSubtitleTrack = 0;
            media.player.play();
            const label = fixture.findItem(media, "mediaSubtitleText");
            verify(label !== null);
            tryCompare(label, "text", "Preview subtitle", 4000);
            verify(label.visible);
            const selector = fixture.findItem(media, "mediaSubtitleTracks");
            verify(selector !== null);
            selector.activated(0);
            compare(label.text, "");
            compare(label.visible, false);
            fixture.passed = true;
        }
        function cleanupTestCase() { if (fixture.passed) console.log("FIXTURE PASS"); Qt.callLater(Qt.quit); }
    }
}
