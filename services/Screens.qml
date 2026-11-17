pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

Singleton {
    id: root

    // ShellScreen.name has no change signal in Quickshell; re-poll briefly while
    // newly attached wl_output screens still report an empty name before xdg_output.done.
    property int _rev: 0
    property int _pendingTicks: 0
    property string _lastNames: ""

    readonly property list<ShellScreen> screens: {
        void root._rev;
        return Quickshell.screens.filter(s => s && s.name !== "" && GlobalConfig.forScreen(s.name).enabled);
    }

    function _knownNamesKey(): string {
        return Quickshell.screens.filter(s => s && s.name !== "").map(s => s.name).join("\n");
    }

    function _checkPending(): void {
        const key = root._knownNamesKey();
        if (key !== root._lastNames)
            root._lastNames = key;

        if (Quickshell.screens.some(s => s && s.name === "")) {
            root._pendingTicks = 0;
            namePollTimer.restart();
        } else {
            namePollTimer.stop();
        }
    }

    function isExcluded(screen: ShellScreen): bool {
        return !screen || screen.name === "" || !GlobalConfig.forScreen(screen.name).enabled;
    }

    Component.onCompleted: root._checkPending()

    Timer {
        id: namePollTimer

        interval: 50
        repeat: true
        onTriggered: {
            root._pendingTicks++;
            const key = root._knownNamesKey();
            if (key !== root._lastNames) {
                root._lastNames = key;
                root._rev++;
            }
            if (!Quickshell.screens.some(s => s && s.name === "") || root._pendingTicks >= 40)
                stop();
        }
    }

    Connections {
        function onScreensChanged(): void {
            root._checkPending();
        }

        target: Quickshell
    }
}
