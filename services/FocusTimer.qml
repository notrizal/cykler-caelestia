pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.I18n
import Caelestia.Services

// Hybrid Focus Timer state:
// - When io.github.focustimerhq.FocusTimer (formerly GNOME Pomodoro) is running on the session bus,
//   all timing, phase transitions, controls (+extend, pause, skip), and reopen-delay preferences sync
//   live over D-Bus via FocusTimerService.
// - When the external app is not running, the built-in local Pomodoro timer keeps working standalone.
// - Drives the desktop FocusCard, the Notch FocusSegment/Prompt, and the layer-shell Break Overlay.
Singleton {
    id: root

    readonly property bool connected: FocusTimerService.connected
    readonly property string phase: {
        if (connected)
            return FocusTimerService.state;
        return localActive || localPhase !== "pomodoro" ? localPhase : (localRunning ? "pomodoro" : "stopped");
    }
    readonly property bool active: connected ? FocusTimerService.active : localActive
    readonly property bool running: connected ? FocusTimerService.running : localRunning
    readonly property bool paused: connected ? FocusTimerService.paused : (!localRunning && localActive && localRemaining > 0)
    readonly property bool isBreak: connected ? FocusTimerService.isBreak : (!localWaitingForInput && (localPhase === "short-break" || localPhase === "long-break"))
    readonly property bool waitingForInput: connected ? FocusTimerService.waitingForInput : localWaitingForInput
    readonly property int durationSecs: connected ? FocusTimerService.durationSecs : localDurationSecs
    readonly property int remaining: connected ? FocusTimerService.remainingSecs : localRemaining
    readonly property real progress: {
        if (connected)
            return FocusTimerService.progress;
        return durationSecs > 0 ? Math.max(0, Math.min(1, 1 - remaining / durationSecs)) : 0;
    }
    readonly property int reopenDelaySecs: 10

    readonly property string display: {
        const secs = Math.max(0, remaining);
        const m = Math.floor(secs / 60);
        const s = secs % 60;
        return `${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
    }

    readonly property string phaseLabel: {
        if (waitingForInput)
            return Tr.tr("Get ready");
        if (!active) {
            if (!connected && localRemaining <= 0)
                return Tr.tr("Session complete");
            return Tr.tr("Ready to focus");
        }
        if (phase === "short-break")
            return paused ? Tr.tr("Short Break (Paused)") : Tr.tr("Short Break");
        if (phase === "long-break")
            return paused ? Tr.tr("Long Break (Paused)") : Tr.tr("Long Break");
        if (phase === "pomodoro")
            return paused ? Tr.tr("Paused") : Tr.tr("Focusing");
        return Tr.tr("Ready to focus");
    }

    // Show interactive "Pomodoro about to end" prompt in the Notch right before a work block ends
    // (or whenever FocusTimer emits ConfirmAdvancement), and a "Get ready" prompt after a break ends
    // while waiting for the user's mouse/keyboard input to start the next Pomodoro.
    readonly property int promptLeadSecs: durationSecs >= 60 ? 15 : 8
    readonly property bool nearEnd: phase === "pomodoro" && running && !waitingForInput && remaining > 0 && remaining <= promptLeadSecs && durationSecs >= 20
    readonly property bool promptShown: active && (waitingForInput || (!isBreak && (confirmPending || (nearEnd && !promptDismissedForBlock))))

    // GNOME-style fullscreen break overlay:
    // - Opens automatically on break start, hides on cursor movement/keypress, reopens on idle.
    // - Automatically disappears as soon as the break finishes.
    readonly property bool overlayVisible: active && isBreak && running && !overlayDismissed

    property int localDurationSecs: 25 * 60
    property int localBreakSecs: 5 * 60
    property int localRemaining: localDurationSecs
    property bool localRunning: false
    property bool localActive: false
    property bool localWaitingForInput: false
    property string localPhase: "pomodoro"

    property bool confirmPending: false
    property bool promptDismissedForBlock: false
    property bool overlayDismissed: false

    function toggle(): void {
        if (waitingForInput) {
            onUserInput();
            return;
        }
        if (connected) {
            FocusTimerService.toggle();
            return;
        }
        if (localRemaining <= 0)
            localRemaining = localPhase === "pomodoro" ? localDurationSecs : localBreakSecs;
        localActive = true;
        localRunning = !localRunning;
    }

    function reset(): void {
        confirmPending = false;
        promptDismissedForBlock = false;
        overlayDismissed = false;
        localWaitingForInput = false;
        if (connected) {
            FocusTimerService.reset();
            return;
        }
        localRunning = false;
        localActive = false;
        localPhase = "pomodoro";
        localRemaining = localDurationSecs;
    }

    function skip(): void {
        confirmPending = false;
        promptDismissedForBlock = false;
        localWaitingForInput = false;
        if (connected) {
            FocusTimerService.skip();
            return;
        }
        if (localPhase === "pomodoro") {
            localPhase = "short-break";
            localRemaining = localBreakSecs;
            localActive = true;
            localRunning = true;
            overlayDismissed = false;
        } else {
            localPhase = "pomodoro";
            localRemaining = localDurationSecs;
            localActive = true;
            localRunning = true;
            overlayDismissed = false;
        }
    }

    function extendMins(mins: int): void {
        const secs = mins * 60;
        confirmPending = false;
        promptDismissedForBlock = false;
        if (connected) {
            FocusTimerService.extendSecs(secs);
            return;
        }
        localRemaining += secs;
        localDurationSecs = Math.max(localDurationSecs, localRemaining);
    }

    function takeBreakNow(): void {
        confirmPending = false;
        promptDismissedForBlock = true;
        if (connected) {
            if (phase === "pomodoro")
                FocusTimerService.skip();
            else
                FocusTimerService.advance();
            return;
        }
        if (localPhase === "pomodoro")
            skip();
    }

    function dismissPrompt(): void {
        confirmPending = false;
        promptDismissedForBlock = true;
    }

    function dismissOverlay(): void {
        if (waitingForInput) {
            onUserInput();
            return;
        }
        if (overlayVisible)
            overlayDismissed = true;
    }

    function onUserInput(): void {
        if (waitingForInput) {
            overlayDismissed = false;
            if (connected) {
                FocusTimerService.startNextAfterBreak();
            } else {
                localWaitingForInput = false;
                localPhase = "pomodoro";
                localRemaining = localDurationSecs;
                localActive = true;
                localRunning = true;
            }
            return;
        }
        if (overlayVisible)
            overlayDismissed = true;
    }

    function adjust(mins: int): void {
        if (connected) {
            if (active)
                FocusTimerService.extendSecs(mins * 60);
            else
                FocusTimerService.showPreferences("timer");
            return;
        }
        if (localRunning)
            return;
        localDurationSecs = Math.max(60, localDurationSecs + mins * 60);
        localRemaining = localDurationSecs;
    }

    function openApp(): void {
        if (connected)
            FocusTimerService.showWindow("");
        else
            launchApp();
    }

    function launchApp(): void {
        Quickshell.execDetached(["flatpak", "run", "io.github.focustimerhq.FocusTimer"]);
    }

    onPhaseChanged: {
        promptDismissedForBlock = false;
        confirmPending = false;
        overlayDismissed = false;
    }

    onNearEndChanged: {
        // If user extended the session back above promptLeadSecs, allow warning again later
        if (!nearEnd && remaining > promptLeadSecs + 2)
            promptDismissedForBlock = false;
    }

    Connections {
        function onConfirmRequested(): void {
            root.confirmPending = true;
        }

        target: FocusTimerService
    }

    // Reopen the break screen overlay automatically if the user stops moving/typing during a break
    IdleMonitor {
        enabled: root.active && root.isBreak && root.running && root.overlayDismissed && !root.waitingForInput
        timeout: Math.max(3, root.reopenDelaySecs)
        respectInhibitors: false
        onIsIdleChanged: {
            if (isIdle && root.isBreak && root.running)
                root.overlayDismissed = false;
        }
    }

    // Also listen for any activity resumption via Wayland IdleMonitor when waiting for input after break
    IdleMonitor {
        enabled: root.waitingForInput
        timeout: 1
        respectInhibitors: false
        onIsIdleChanged: {
            if (!isIdle && root.waitingForInput)
                root.onUserInput();
        }
    }

    // Standalone local fallback timer when external Focus Timer app isn't running
    Timer {
        interval: 1000
        repeat: true
        running: !root.connected && root.localRunning
        onTriggered: {
            root.localRemaining--;
            if (root.localRemaining <= 0) {
                if (root.localPhase === "pomodoro") {
                    root.localPhase = "short-break";
                    root.localRemaining = root.localBreakSecs;
                    root.overlayDismissed = false;
                } else {
                    // Break finished: hold the next Pomodoro until the user provides any input
                    root.localRunning = false;
                    root.localPhase = "pomodoro";
                    root.localRemaining = root.localDurationSecs;
                    root.localWaitingForInput = true;
                    root.overlayDismissed = false;
                }
            }
        }
    }
}
