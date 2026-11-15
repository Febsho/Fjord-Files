pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property url source: ""
    property url posterSource: ""
    property bool video: false
    property bool autoPlay: false
    property bool startMuted: false
    property bool compact: false
    property bool mediaStarted: false
    property string currentSubtitle: ""
    readonly property string errorMessage: player.error !== MediaPlayer.NoError
        ? (player.errorString || I18n.tr("This file could not be opened", "large preview placeholder")) : ""
    readonly property alias player: player
    readonly property alias audioOutput: audioOutput
    signal fullScreenRequested()
    onStartMutedChanged: audioOutput.muted = startMuted
    readonly property var speeds: [0.5, 0.75, 1, 1.25, 1.5, 2]
    // QMediaMetaData keys: Title = 0, Author = 1, AlbumTitle = 18, AlbumArtist = 19.
    readonly property string mediaTitle: player.metaData.stringValue(0)
    readonly property string mediaAuthor: player.metaData.stringValue(1) || player.metaData.stringValue(19) || player.metaData.stringValue(20) || player.metaData.stringValue(23)
    readonly property string mediaAlbum: player.metaData.stringValue(18)

    function trackLabels(tracks, kind) {
        const result = [I18n.tr("Off", "disabled media track")];
        for (let i = 0; i < tracks.length; ++i) {
            // QMediaMetaData keys: Title = 0, Language = 6.
            const title = tracks[i].stringValue(0);
            const language = tracks[i].stringValue(6);
            const detail = [title, language].filter(part => part && part !== "AnyLanguage").join(" — ");
            result.push(kind + " " + (i + 1) + (detail ? ": " + detail : ""));
        }
        return result;
    }

    function time(ms) {
        const seconds = Math.floor(Math.max(0, ms) / 1000);
        const minutes = Math.floor(seconds / 60);
        return Math.floor(minutes / 60) > 0
            ? Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0")
            : minutes + ":" + String(seconds % 60).padStart(2, "0");
    }

    MediaPlayer {
        id: player
        source: root.source
        audioOutput: AudioOutput { id: audioOutput }
        videoOutput: videoOutput
        onSourceChanged: {
            root.currentSubtitle = "";
            root.mediaStarted = false;
            audioOutput.muted = root.startMuted;
            stop();
            if (root.autoPlay && source.toString() !== "") {
                root.mediaStarted = true;
                play();
            }
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: options.top
        visible: root.video
        fillMode: root.compact ? VideoOutput.PreserveAspectCrop : VideoOutput.PreserveAspectFit
    }

    Image {
        anchors.fill: videoOutput
        z: 1
        visible: root.video && !root.mediaStarted && root.posterSource.toString() !== ""
        source: root.posterSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: root.fullScreenRequested()
    }

    Connections {
        target: videoOutput.videoSink
        function onSubtitleTextChanged(text) { root.currentSubtitle = text; }
    }

    Text {
        objectName: "mediaSubtitleText"
        anchors.horizontalCenter: videoOutput.horizontalCenter
        anchors.bottom: controls.top
        anchors.bottomMargin: Theme.spacingM
        width: Math.max(0, videoOutput.width - Theme.spacingXL * 2)
        text: root.currentSubtitle
        visible: root.video && text !== ""
        color: "white"
        style: Text.Outline
        styleColor: "black"
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font.pixelSize: Theme.fontSizeLarge
    }

    ColumnLayout {
        anchors.centerIn: videoOutput
        width: Math.max(0, videoOutput.width - Theme.spacingXL * 2)
        visible: !root.video && root.errorMessage === ""
        StyledText {
            objectName: "mediaTitle"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.mediaTitle || I18n.tr("Audio", "audio preview")
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            elide: Text.ElideRight
        }
        StyledText {
            objectName: "mediaArtist"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: root.mediaAuthor
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
        StyledText {
            objectName: "mediaAlbum"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: root.mediaAlbum
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
    }

    GlassViewerControls {
        id: controls
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: options.top
        refractionSource: root.video ? videoOutput : null
        spacing: Theme.spacingS

        DActionButton {
            iconName: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
            tooltipText: player.playbackState === MediaPlayer.PlayingState ? I18n.tr("Pause", "media playback") : I18n.tr("Play", "media playback")
            onClicked: {
                if (player.playbackState === MediaPlayer.PlayingState)
                    player.pause();
                else {
                    root.mediaStarted = true;
                    player.play();
                }
            }
        }
        DActionButton {
            visible: root.video
            iconName: audioOutput.muted ? "volume_off" : "volume_up"
            tooltipText: audioOutput.muted ? I18n.tr("Unmute", "media preview audio") : I18n.tr("Mute", "media preview audio")
            Accessible.name: tooltipText
            onClicked: audioOutput.muted = !audioOutput.muted
        }
        StyledText {
            text: root.time(player.position)
            color: Theme.surfaceVariantText
        }
        Slider {
            id: seek
            Layout.fillWidth: true
            from: 0
            to: Math.max(1, player.duration)
            enabled: player.seekable && player.duration > 0
            Binding on value { when: !seek.pressed; value: player.position }
            onMoved: player.position = value
            Accessible.name: I18n.tr("Seek", "media playback position")
        }
        StyledText {
            text: root.time(player.duration)
            color: Theme.surfaceVariantText
        }
    }

    Flow {
        id: options
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Theme.spacingS

        StyledText {
            visible: !root.compact
            text: I18n.tr("Volume", "media playback volume")
            color: Theme.surfaceVariantText
        }
        Slider {
            id: volume
            objectName: "mediaVolume"
            width: 110
            visible: !root.compact
            from: 0
            to: 1
            value: audioOutput.volume
            onMoved: audioOutput.volume = value
            Accessible.name: I18n.tr("Volume", "media playback volume")
        }
        ComboBox {
            id: rate
            objectName: "mediaRate"
            visible: !root.compact
            width: 90
            model: root.speeds.map(speed => speed + "×")
            currentIndex: root.speeds.indexOf(player.playbackRate)
            onActivated: index => player.playbackRate = root.speeds[index]
            Accessible.name: I18n.tr("Playback speed", "media playback speed")
        }
        ComboBox {
            id: audioTracks
            objectName: "mediaAudioTracks"
            visible: !root.compact
            width: 160
            model: root.trackLabels(player.audioTracks, I18n.tr("Audio", "audio track"))
            enabled: player.audioTracks.length > 0
            currentIndex: player.activeAudioTrack + 1
            onActivated: index => player.activeAudioTrack = index - 1
            Accessible.name: I18n.tr("Audio track", "media audio track selection")
        }
        ComboBox {
            id: subtitleTracks
            objectName: "mediaSubtitleTracks"
            visible: !root.compact
            width: 160
            model: root.trackLabels(player.subtitleTracks, I18n.tr("Subtitle", "subtitle track"))
            enabled: player.subtitleTracks.length > 0
            currentIndex: player.activeSubtitleTrack + 1
            onActivated: index => {
                root.currentSubtitle = "";
                player.activeSubtitleTrack = index - 1;
            }
            Accessible.name: I18n.tr("Subtitle track", "media subtitle track selection")
        }
    }

}
