pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Rectangle {
    id: root

    default property alias contentData: content.data
    property color baseColor: Theme.foregroundColor(Theme.cardSurface, true)
    property bool highlightsEnabled: true
    property bool edgeLightingEnabled: true
    property Item refractionSource: null
    property bool refractionLive: true
    property var refractionRevision: 0

    readonly property real strength: Theme.glassMaterialStrength
    readonly property bool refractionEnabled: root.refractionSource !== null && root.strength > 0 && !Theme.performanceMode
    readonly property bool refractionSourceLive: refractionTexture.live
    readonly property rect refractionSourceRect: refractionTexture.sourceRect
    readonly property size refractionTextureSize: refractionTexture.textureSize
    readonly property color materialColor: Theme.blend(baseColor, Theme.glassTint, strength * 0.055)

    function refreshStaticRefraction() {
        if (!refractionEnabled || refractionLive)
            return;
        refractionTexture.scheduleUpdate();
    }

    onRefractionEnabledChanged: refreshStaticRefraction()
    onRefractionLiveChanged: refreshStaticRefraction()
    onRefractionRevisionChanged: refreshStaticRefraction()
    onRefractionSourceRectChanged: refreshStaticRefraction()
    onRefractionTextureSizeChanged: refreshStaticRefraction()

    Component.onCompleted: refreshStaticRefraction()

    clip: false
    color: materialColor
    topLeftRadius: Theme.cornerRadiusM
    topRightRadius: topLeftRadius
    bottomLeftRadius: topLeftRadius
    bottomRightRadius: topLeftRadius
    border.width: root.edgeLightingEnabled && root.strength > 0 ? 1 : 0
    border.color: Theme.withAlpha(Theme.surfaceText, Theme.glassEdgeAlpha)

    gradient: root.highlightsEnabled && root.strength > 0 ? glassGradient : null

    ShaderEffectSource {
        id: refractionTexture

        width: root.width
        height: root.height
        sourceItem: root.refractionSource
        sourceRect: {
            if (root.refractionSource === null)
                return Qt.rect(0, 0, 0, 0);
            const origin = root.refractionSource.mapFromItem(root, 0, 0);
            return Qt.rect(origin.x, origin.y, root.width, root.height);
        }
        textureSize: Qt.size(Math.max(1, Math.ceil(root.width * 0.5)), Math.max(1, Math.ceil(root.height * 0.5)))
        live: root.refractionEnabled && root.refractionLive
        hideSource: false
        visible: false
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.refractionEnabled
        z: 0
        blending: true
        fragmentShader: Qt.resolvedUrl("../shaders/glass-refraction.frag.qsb")
        property var source: refractionTexture
        property size sourceSize: Qt.size(width, height)
        property real cornerRadius: root.topLeftRadius
        property real displacement: root.strength * 0.012
        property real refractionOpacity: root.strength * 0.22
        property real saturation: root.strength * 0.12
    }

    Gradient {
        id: glassGradient

        GradientStop {
            position: 0
            color: Theme.blend(root.materialColor, Theme.surface, Theme.glassHighlightAlpha)
        }
        GradientStop {
            position: 0.16
            color: Theme.blend(root.materialColor, Theme.surface, Theme.glassHighlightAlpha * 0.20)
        }
        GradientStop {
            position: 0.58
            color: root.materialColor
        }
        GradientStop {
            position: 1
            color: Theme.blend(root.materialColor, Theme.primary, root.strength * 0.025)
        }
    }

    Item {
        id: content

        anchors.fill: parent
        z: 1
    }
}
