pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import Caelestia.State
import qs.services
import qs.utils

// Automatically pauses animated video wallpapers on battery or when covered by windows,
// combined with the manual play/pause toggle in Utilities (PersistentState.wallpaperPlaying).
Singleton {
    id: root

    readonly property bool pauseOnBattery: GlobalConfig.background.pauseVideoOnBattery
    readonly property bool pauseOnWindowOverlap: GlobalConfig.background.pauseVideoBehindWindows
    readonly property bool paused: !PersistentState.wallpaperPlaying || autoPaused

    property bool autoPaused: false
    property string pauseReason: "None"

    function recalculate(): void {
        let nextPaused = false;
        let reason = "None";

        if (pauseOnBattery && PowerSaving.onBattery) {
            nextPaused = true;
            reason = "Battery";
        } else if (pauseOnWindowOverlap) {
            const monitor = Hypr.focusedMonitor;
            const ws = monitor?.activeWorkspace ?? Hypr.focusedWorkspace;

            if (ws) {
                const toplevels = ws.toplevels.values;
                if (toplevels.some(t => (t.lastIpcObject?.fullscreen ?? 0) > 0)) {
                    nextPaused = true;
                    reason = "Fullscreen";
                } else if (toplevels.length >= 2) {
                    nextPaused = true;
                    reason = "2+ windows";
                } else if (monitor) {
                    const screen = Quickshell.screens.find(s => s.name === monitor.name);
                    if (screen) {
                        const screenArea = screen.width * screen.height;
                        if (screenArea > 0) {
                            const threshold = screenArea * 0.7;
                            for (const t of toplevels) {
                                const size = t.lastIpcObject?.size;
                                if (size && size.length >= 2 && size[0] * size[1] >= threshold) {
                                    nextPaused = true;
                                    reason = "70% area rule";
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        autoPaused = nextPaused;
        pauseReason = reason;
    }

    function decoderCliValue(decoder: int): string {
        switch (decoder) {
        case VideoHwDecoder.None:
            return "none";
        case VideoHwDecoder.Vaapi:
            return "vaapi";
        case VideoHwDecoder.Vdpau:
            return "vdpau";
        case VideoHwDecoder.Cuda:
            return "cuda";
        case VideoHwDecoder.Vulkan:
            return "vulkan";
        case VideoHwDecoder.Drm:
            return "drm";
        case VideoHwDecoder.Auto:
        default:
            return "auto";
        }
    }

    function syncHwDecoderCache(): void {
        const val = decoderCliValue(GlobalConfig.background.videoHwDecoder);
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/hwDecoder.txt\"", "_", Paths.cache, val]);
    }

    onPauseOnBatteryChanged: recalculate()
    onPauseOnWindowOverlapChanged: recalculate()

    Component.onCompleted: {
        recalculate();
        syncHwDecoderCache();
    }

    Connections {
        function onVideoHwDecoderChanged(): void {
            root.syncHwDecoderCache();
        }

        target: GlobalConfig.background
    }

    Connections {
        function onFocusedWorkspaceChanged(): void {
            root.recalculate();
        }

        function onFocusedMonitorChanged(): void {
            root.recalculate();
        }

        function onRawEvent(event: var): void {
            const n = event.name;
            if (n.startsWith("workspace") || n.startsWith("activewindow") || n.startsWith("createworkspace") || n.startsWith("destroyworkspace") || ["fullscreen", "changefloatingmode", "minimize", "movewindow", "openwindow", "closewindow", "moveworkspace", "focusedmon"].includes(n))
                recalcTimer.restart();
        }

        target: Hyprland
    }

    Connections {
        function onOnBatteryChanged(): void {
            recalcTimer.restart();
        }

        target: PowerSaving
    }

    Timer {
        id: recalcTimer

        interval: 50
        onTriggered: root.recalculate()
    }

    // Re-evaluate shortly after startup once Hyprland and Quickshell screens settle
    Timer {
        id: startupTimer

        property int attempts: 0

        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.recalculate();
            attempts++;
            if (attempts >= 5)
                running = false;
        }
    }
}
