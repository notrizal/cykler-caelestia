pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// GNOME Pomodoro-style fullscreen break screen overlay, styled with Caelestia's blurred
// theme surface and showing ONLY the countdown time:
// - Covers every monitor on WlrLayer.Overlay during breaks with compositor blur.
// - Dismisses immediately on deliberate cursor movement or keypress, and reopens on idle.
// - Automatically disappears when break ends, while keeping a 0-opacity input catcher active
//   until the user moves the mouse or presses any key to start the next Pomodoro.
Scope {
    id: root

    readonly property string namespaceMatch: "caelestia-focus-break-overlay"
    readonly property bool blurred: !!Hypr.options["decoration:blur:enabled"]

    property bool rulesApplied: false

    function ensureRules(): void {
        if (rulesApplied)
            return;
        rulesApplied = true;

        let rule, on;
        if (Hypr.usingLua) {
            rule = `eval hl.layer_rule({ match = { namespace = "${namespaceMatch}" }, %1 = %2 })`;
            on = true;
        } else {
            rule = `keyword layerrule %1 %2, match:namespace ${namespaceMatch}`;
            on = 1;
        }
        Hypr.extras.batchMessage([rule.arg("blur").arg(on), rule.arg("ignore_alpha").arg(0.02), rule.arg("animation").arg(Hypr.usingLua ? '"fade"' : "fade")]);
    }

    Component.onCompleted: rulesTimer.start()

    Timer {
        id: rulesTimer

        interval: 1500
        onTriggered: root.ensureRules()
    }

    Connections {
        function onConfigReloaded(): void {
            root.rulesApplied = false;
            root.ensureRules();
        }

        target: Hypr
    }

    Variants {
        model: Screens.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool open: FocusTimer.overlayVisible
            readonly property bool waitingInput: FocusTimer.waitingForInput
            readonly property bool trapActive: open || waitingInput
            readonly property bool wanted: open || reveal > 0.005 || waitingInput

            property real reveal: open ? 1 : 0
            property bool armDismiss: false
            property real startMouseX: -1
            property real startMouseY: -1

            function rearmInputGuard(delayMs: int): void {
                startMouseX = -1;
                startMouseY = -1;
                armDismiss = false;
                armTimer.interval = delayMs;
                armTimer.restart();
                keyTrap.forceActiveFocus();
            }

            screen: modelData
            name: "focus-break-overlay"
            visible: wanted
            implicitWidth: screen.width
            implicitHeight: screen.height
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: trapActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: trapActive ? null : emptyRegion

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            onOpenChanged: {
                if (open) {
                    root.ensureRules();
                    rearmInputGuard(900);
                } else if (!waitingInput) {
                    armDismiss = false;
                    armTimer.stop();
                }
            }

            onWaitingInputChanged: {
                if (waitingInput) {
                    root.ensureRules();
                    rearmInputGuard(250);
                } else if (!open) {
                    armDismiss = false;
                    armTimer.stop();
                }
            }

            Region {
                id: emptyRegion
            }

            // Grace delay after appearing so residual mouse movement from clicking "Skip" / "Break"
            // or initial Wayland pointer-enter synthesis does not dismiss the overlay immediately.
            Timer {
                id: armTimer

                interval: 900
                onTriggered: {
                    win.startMouseX = -1;
                    win.startMouseY = -1;
                    win.armDismiss = true;
                    keyTrap.forceActiveFocus();
                }
            }

            Behavior on reveal {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Item {
                id: keyTrap

                anchors.fill: parent
                focus: win.trapActive

                Keys.onPressed: event => {
                    if (!win.armDismiss)
                        return;
                    FocusTimer.onUserInput();
                    event.accepted = true;
                }

                // Caelestia-themed blurred overlay background
                StyledRect {
                    anchors.fill: parent
                    visible: win.reveal > 0.001
                    color: Qt.alpha(Colours.palette.m3scrim, root.blurred ? 0.28 : 0.62)
                    opacity: win.reveal
                }

                StyledRect {
                    anchors.fill: parent
                    visible: win.reveal > 0.001
                    color: Qt.alpha(Colours.palette.m3surface, root.blurred ? 0.52 : 0.86)
                    opacity: win.reveal
                }

                // Pure countdown time only — no icons, cards, or extra text
                StyledText {
                    anchors.centerIn: parent
                    visible: win.reveal > 0.001
                    text: FocusTimer.display
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(96).weight(Font.Bold).build()
                    opacity: win.reveal
                }

                WheelHandler {
                    onWheel: {
                        if (win.trapActive && win.armDismiss)
                            FocusTimer.onUserInput();
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons

                    onPressed: {
                        if (win.trapActive && win.armDismiss)
                            FocusTimer.onUserInput();
                    }
                    onPositionChanged: mouse => {
                        if (!win.trapActive || !win.armDismiss)
                            return;
                        if (win.startMouseX < 0 || win.startMouseY < 0) {
                            win.startMouseX = mouse.x;
                            win.startMouseY = mouse.y;
                            return;
                        }
                        const threshold = win.waitingInput ? 4 : 14;
                        if (Math.hypot(mouse.x - win.startMouseX, mouse.y - win.startMouseY) > threshold)
                            FocusTimer.onUserInput();
                    }
                }
            }
        }
    }
}
