import QtQuick
import QtMultimedia

// Dual-player (A/B ping-pong) video renderer for smooth wallpaper switches without stalling the UI thread.
Item {
    id: root

    property url videoSource
    property bool playing: true
    property int fillMode: VideoOutput.PreserveAspectCrop
    readonly property bool videoReady: _usePlayerA ? _readyA : _readyB

    property bool _usePlayerA: true
    property bool _swapping: false
    property bool _pendingSwapToA: true
    property bool _readyA: false
    property bool _readyB: false
    property bool _forceFrameA: false
    property bool _forceFrameB: false

    function _activePlayer(): MediaPlayer {
        if (_swapping)
            return _pendingSwapToA ? playerA : playerB;
        return _usePlayerA ? playerA : playerB;
    }

    function _loadSource(url: url): void {
        const targetStr = url.toString();
        if (!targetStr) {
            deferredPlayTimer.stop();
            _swapping = false;
            _readyA = false;
            _readyB = false;
            _forceFrameA = false;
            _forceFrameB = false;
            playerA.source = "";
            playerB.source = "";
            return;
        }

        if (playerA.source.toString() === "" && playerB.source.toString() === "") {
            _usePlayerA = true;
            _readyA = false;
            playerA.source = url;
            return;
        }

        if (_usePlayerA) {
            if (playerA.source === url)
                return;
            _readyB = false;
            playerB.source = url;
        } else {
            if (playerB.source === url)
                return;
            _readyA = false;
            playerA.source = url;
        }
    }

    function _performSwap(swapToA: bool): void {
        _swapping = true;
        _pendingSwapToA = swapToA;

        const oldPlayer = swapToA ? playerB : playerA;
        oldPlayer.pause();
        deferredPlayTimer.restart();
    }

    function _executeDeferredSwap(): void {
        const swapToA = _pendingSwapToA;
        const newPlayer = swapToA ? playerA : playerB;
        const oldPlayer = swapToA ? playerB : playerA;

        if (root.playing) {
            newPlayer.play();
        } else {
            if (swapToA)
                _forceFrameA = true;
            else
                _forceFrameB = true;
            newPlayer.play();
        }

        root._usePlayerA = swapToA;

        Qt.callLater(() => {
            oldPlayer.source = "";
            if (swapToA)
                root._readyB = false;
            else
                root._readyA = false;
            root._swapping = false;

            const wanted = root.videoSource.toString();
            if (wanted && newPlayer.source.toString() !== wanted)
                root._loadSource(root.videoSource);
        });
    }

    onVideoSourceChanged: _loadSource(videoSource)

    onPlayingChanged: {
        if (!videoSource.toString())
            return;

        const active = _activePlayer();
        if (playing) {
            _forceFrameA = false;
            _forceFrameB = false;
            if (active.mediaStatus === MediaPlayer.LoadedMedia || active.playbackState === MediaPlayer.PausedState)
                active.play();
        } else {
            active.pause();
        }
    }

    Component.onCompleted: {
        if (videoSource.toString())
            _loadSource(videoSource);
    }

    Timer {
        id: deferredPlayTimer

        // Defer play() slightly so picker click feedback paints before decoder startup
        interval: 100
        repeat: false
        onTriggered: root._executeDeferredSwap()
    }

    VideoOutput {
        id: outputA

        anchors.fill: parent
        fillMode: root.fillMode
        endOfStreamPolicy: VideoOutput.KeepLastFrame
        visible: root._usePlayerA
    }

    MediaPlayer {
        id: playerA

        videoOutput: outputA
        audioOutput: null
        loops: MediaPlayer.Infinite
        autoPlay: false

        onErrorOccurred: (error, errorString) => {
            if (error !== MediaPlayer.NoError)
                console.warn("VideoWallpaper A:", errorString);
        }

        onPositionChanged: {
            if (!playerA.source.toString() || position <= 0)
                return;
            root._readyA = true;
            if (root._forceFrameA) {
                root._forceFrameA = false;
                playerA.pause();
            }
        }

        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.LoadedMedia)
                return;

            if (!root._usePlayerA && !root._swapping) {
                root._performSwap(true);
            } else if (root._usePlayerA && !playerB.source.toString() && !root._swapping) {
                root._forceFrameA = !root.playing;
                playerA.play();
            }
        }
    }

    Connections {
        function onVideoFrameChanged(): void {
            if (!playerA.source.toString() || outputA.videoSink.videoSize.width <= 0)
                return;
            root._readyA = true;
            if (root._forceFrameA) {
                root._forceFrameA = false;
                playerA.pause();
            }
        }

        target: outputA.videoSink
    }

    VideoOutput {
        id: outputB

        anchors.fill: parent
        fillMode: root.fillMode
        endOfStreamPolicy: VideoOutput.KeepLastFrame
        visible: !root._usePlayerA
    }

    MediaPlayer {
        id: playerB

        videoOutput: outputB
        audioOutput: null
        loops: MediaPlayer.Infinite
        autoPlay: false

        onErrorOccurred: (error, errorString) => {
            if (error !== MediaPlayer.NoError)
                console.warn("VideoWallpaper B:", errorString);
        }

        onPositionChanged: {
            if (!playerB.source.toString() || position <= 0)
                return;
            root._readyB = true;
            if (root._forceFrameB) {
                root._forceFrameB = false;
                playerB.pause();
            }
        }

        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.LoadedMedia)
                return;

            if (root._usePlayerA && !root._swapping)
                root._performSwap(false);
        }
    }

    Connections {
        function onVideoFrameChanged(): void {
            if (!playerB.source.toString() || outputB.videoSink.videoSize.width <= 0)
                return;
            root._readyB = true;
            if (root._forceFrameB) {
                root._forceFrameB = false;
                playerB.pause();
            }
        }

        target: outputB.videoSink
    }
}
