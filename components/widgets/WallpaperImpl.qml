pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import Caelestia.Multimedia
import Caelestia.Shaders
import qs.services

Item {
    id: root

    readonly property transitionShader shader: {
        CUtils.dependency(Config.background.wallpaperTransition);
        let transition = CUtils.enumToString(Config.background, "wallpaperTransition");
        if (!transition)
            return Shaders.crossfade;

        transition = transition[0].toLowerCase() + transition.slice(1);
        return Shaders[transition] ?? Shaders.crossfade;
    }
    readonly property bool isVideo: allowVideo && Wallpapers.isVideo(settledSource)
    readonly property string stillSource: {
        if (!settledSource)
            return "";
        if (Wallpapers.isVideo(settledSource))
            return Wallpapers.getWallpaperThumb(settledSource, Wallpapers.thumbBusterFor(settledSource));
        return settledSource;
    }
    readonly property url videoUrl: {
        if (!isVideo)
            return "";
        const clean = Wallpapers.cleanPath(settledSource);
        return clean.startsWith("/") ? `file://${clean}` : Qt.resolvedUrl(clean);
    }
    readonly property bool liveReady: isVideo ? (((videoLoader.item as VideoWallpaper)?.videoReady ?? false) || stillLive.ready) : stillLive.ready

    property string source: Wallpapers.current
    property bool allowVideo: true
    property bool paused: WallpaperPauser.paused
    property string settledSource: ""
    property ShaderEffectSource currentCapture: capture1
    property real transitionProgress: 1
    property bool _completed: false
    property bool _capturing: false

    function applySourceChange(): void {
        if (source === settledSource)
            return;

        transitionAnim.stop();
        _capturing = true;

        if (transitionProgress < 1) {
            currentCapture = currentCapture === capture1 ? capture2 : capture1;
            currentCapture.sourceItem = transition;
        } else {
            currentCapture.sourceItem = live;
        }

        currentCapture.visible = true;
        currentCapture.scheduleUpdate();
    }

    onSourceChanged: {
        if (_completed)
            coalesceTimer.restart();
    }

    onTransitionProgressChanged: {
        if (transitionProgress >= 1)
            _capturing = false;
    }

    Component.onCompleted: {
        settledSource = source;
        _completed = true;
    }

    Timer {
        id: coalesceTimer

        // Debounce rapid scrolling in the wallpaper picker so intermediate decoders are skipped
        interval: 80
        repeat: false
        onTriggered: root.applySourceChange()
    }

    NumberAnimation on transitionProgress {
        id: transitionAnim

        running: false
        duration: root.shader.duration * Tokens.anim.durations.scale
        easing: root.shader.easing
        to: 1
    }

    ShaderEffectSource {
        id: capture1

        anchors.fill: parent
        live: false
        visible: false

        onScheduledUpdateCompleted: {
            visible = false;
            transition.from = this;
            root.transitionProgress = 0;
            root.settledSource = root.source;
            if (!root.source) {
                root.transitionProgress = 1;
                return;
            }
            if (root.liveReady)
                transitionAnim.start();
        }
    }

    ShaderEffectSource {
        id: capture2

        anchors.fill: parent
        live: false
        visible: false

        onScheduledUpdateCompleted: {
            visible = false;
            transition.from = this;
            root.transitionProgress = 0;
            root.settledSource = root.source;
            if (!root.source) {
                root.transitionProgress = 1;
                return;
            }
            if (root.liveReady)
                transitionAnim.start();
        }
    }

    Item {
        id: live

        anchors.fill: parent
        layer.enabled: root.transitionProgress < 1 || root._capturing

        Visual {
            id: stillLive

            anchors.fill: parent
            source: root.stillSource
            playing: false
            animate: false

            onReadyChanged: {
                if (stillLive.ready && root.settledSource === root.source && root.transitionProgress < 1 && !transitionAnim.running)
                    transitionAnim.start();
            }
        }

        Loader {
            id: videoLoader

            anchors.fill: parent
            active: root.isVideo
            opacity: ((item as VideoWallpaper)?.videoReady ?? false) ? 1 : 0

            sourceComponent: VideoWallpaper {
                videoSource: root.videoUrl
                playing: !root.paused
            }

            Connections {
                function onVideoReadyChanged(): void {
                    if ((videoLoader.item as VideoWallpaper)?.videoReady && root.settledSource === root.source && root.transitionProgress < 1 && !transitionAnim.running)
                        transitionAnim.start();
                }

                target: videoLoader.item
            }
        }
    }

    ShaderEffect {
        id: transition

        property Item from
        property Item to: live
        property real progress: root.transitionProgress

        anchors.fill: parent
        visible: root.transitionProgress < 1
        fragmentShader: root.shader.url
    }
}
