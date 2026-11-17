pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import qs.services

// Switches all existing and newly opened windows between Hyprland tiling and floating modes.
Singleton {
    id: root

    readonly property bool floatingMode: GlobalConfig.general.floatingWindowMode
    property bool _initialised: false
    property var _pendingNewAddrs: []

    function floatDispatch(address: string, floating: bool): string {
        const target = `address:0x${address}`;
        if (Hypr.usingLua)
            return `hl.dsp.window.float({ float = ${floating ? "true" : "false"}, window = "${target}" })`;
        return `${floating ? "setfloating" : "settiled"} ${target}`;
    }

    function resizeDispatch(address: string, w: int, h: int): string {
        const target = `address:0x${address}`;
        if (Hypr.usingLua)
            return `hl.dsp.window.resize({ exact = true, x = ${w}, y = ${h}, window = "${target}" })`;
        return `resizewindowpixel exact ${w} ${h},${target}`;
    }

    function centerDispatch(address: string): string {
        const target = `address:0x${address}`;
        if (Hypr.usingLua)
            return `hl.dsp.window.center({ window = "${target}" })`;
        return `centerwindow ${target}`;
    }

    function floatSizeForToplevel(toplevel: var): var {
        const ipc = toplevel?.lastIpcObject;
        if (!ipc || !ipc.size)
            return null;

        const mon = Hypr.monitors.values.find(m => m.id === ipc.monitor) ?? Hypr.focusedMonitor;
        const monIpc = mon?.lastIpcObject;
        if (!monIpc || !monIpc.width || !monIpc.height)
            return null;

        const scale = monIpc.scale > 0 ? monIpc.scale : 1;
        const rotated = (monIpc.transform ?? 0) % 2 === 1;
        const monW = (rotated ? monIpc.height : monIpc.width) / scale;
        const monH = (rotated ? monIpc.width : monIpc.height) / scale;

        const curW = Number(ipc.size[0] ?? 0);
        const curH = Number(ipc.size[1] ?? 0);
        if (curW < monW * 0.82 && curH < monH * 0.82)
            return null;

        return {
            w: Math.round(Math.max(720, monW * 0.72)),
            h: Math.round(Math.max(520, monH * 0.76))
        };
    }

    function applyToToplevel(toplevel: var, floating: bool, cmds: var): void {
        const ipc = toplevel?.lastIpcObject;
        if (!ipc || !ipc.mapped)
            return;
        if ((ipc.fullscreen ?? 0) > 0)
            return;

        const addr = String(toplevel.address || "").replace(/^0x/, "");
        if (!addr)
            return;

        if (floating) {
            if (!ipc.floating) {
                cmds.push(`dispatch ${floatDispatch(addr, true)}`);
                const targetSize = floatSizeForToplevel(toplevel);
                if (targetSize) {
                    cmds.push(`dispatch ${resizeDispatch(addr, targetSize.w, targetSize.h)}`);
                    cmds.push(`dispatch ${centerDispatch(addr)}`);
                }
            }
        } else if (ipc.floating && !ipc.pinned) {
            cmds.push(`dispatch ${floatDispatch(addr, false)}`);
        }
    }

    function applyToAllWindows(): void {
        const cmds = [];
        for (const t of Hypr.toplevels.values)
            applyToToplevel(t, root.floatingMode, cmds);

        if (cmds.length > 0)
            Hypr.extras.batchMessage(cmds);
    }

    function processPendingNewWindows(): void {
        if (!root.floatingMode || _pendingNewAddrs.length === 0) {
            _pendingNewAddrs = [];
            return;
        }

        const addrs = _pendingNewAddrs;
        _pendingNewAddrs = [];
        const cmds = [];

        for (const addr of addrs) {
            const toplevel = Hypr.toplevels.values.find(t => String(t.address || "").replace(/^0x/, "") === addr);
            if (toplevel) {
                applyToToplevel(toplevel, true, cmds);
            } else {
                cmds.push(`dispatch ${floatDispatch(addr, true)}`);
            }
        }

        if (cmds.length > 0)
            Hypr.extras.batchMessage(cmds);
    }

    onFloatingModeChanged: {
        if (_initialised)
            applyToAllWindows();
    }

    Component.onCompleted: {
        _initialised = true;
        if (floatingMode)
            startupTimer.restart();
    }

    Timer {
        id: startupTimer

        interval: 800
        repeat: false
        onTriggered: root.applyToAllWindows()
    }

    Timer {
        id: newWindowTimer

        interval: 40
        repeat: false
        onTriggered: root.processPendingNewWindows()
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (!root.floatingMode)
                return;

            if (event.name === "openwindow") {
                const parts = String(event.data || "").split(",");
                const addr = (parts[0] ?? "").trim().replace(/^0x/, "");
                if (addr && !root._pendingNewAddrs.includes(addr)) {
                    root._pendingNewAddrs = [...root._pendingNewAddrs, addr];
                    newWindowTimer.restart();
                }
            }
        }

        target: Hyprland
    }

    IpcHandler {
        function toggle(): void {
            GlobalConfig.general.floatingWindowMode = !GlobalConfig.general.floatingWindowMode;
        }

        function setFloating(enabled: bool): void {
            GlobalConfig.general.floatingWindowMode = enabled;
        }

        target: "windowMode"
    }
}
