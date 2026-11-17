pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.utils

Singleton {
    id: root

    // Revision counter bumped when desktop entries or Hyprland windows change
    property int revision: 0
    readonly property string activeAddress: String(Hypr.activeToplevel?.address || "").replace(/^0x/, "")

    function normalizeId(value: string): string {
        return String(value || "").trim().toLowerCase().replace(/\.desktop$/, "");
    }

    function cleanAddress(client: var): string {
        return String(client?.address || "").replace(/^0x/, "");
    }

    function isMinimized(client: var): bool {
        return String(client?.lastIpcObject?.workspace?.name || "") === "special:minimized";
    }

    function workspaceLabel(client: var): string {
        const wsName = String(client?.lastIpcObject?.workspace?.name || "");
        if (wsName === "special:minimized")
            return Tr.tr("Minimized");
        if (wsName.startsWith("special:"))
            return Hypr.trimWsName(wsName);
        const wsId = client?.lastIpcObject?.workspace?.id ?? client?.workspace?.id ?? 0;
        return wsId > 0 ? Tr.tr("WS %1").arg(wsId) : "";
    }

    function entryForId(appId: string): DesktopEntry {
        const target = normalizeId(appId);
        if (!target)
            return null;

        const direct = DesktopEntries.byId(appId);
        if (direct)
            return direct;

        for (const entry of DesktopEntries.applications.values) {
            if (normalizeId(entry.id) === target)
                return entry;
        }
        return DesktopEntries.heuristicLookup(appId) ?? null;
    }

    function entryForWindow(client: var): DesktopEntry {
        const ipc = client?.lastIpcObject;
        const cls = String(ipc?.class || "");
        const initialCls = String(ipc?.initialClass || "");
        const candidates = [cls, initialCls].filter(s => s.length > 0);

        for (const c of candidates) {
            const norm = normalizeId(c);
            for (const entry of DesktopEntries.applications.values) {
                if (normalizeId(entry.id) === norm)
                    return entry;
            }
            for (const entry of DesktopEntries.applications.values) {
                if (entry.startupClass && normalizeId(entry.startupClass) === norm)
                    return entry;
            }
        }

        for (const c of candidates) {
            const found = DesktopEntries.heuristicLookup(c);
            if (found)
                return found;
        }
        return null;
    }

    function iconSource(entry: DesktopEntry, fallbackClass: string): string {
        if (entry?.icon) {
            const resolved = Quickshell.iconPath(entry.icon, true);
            if (resolved)
                return resolved;
            return Quickshell.iconPath(entry.icon, "application-x-executable");
        }
        return Icons.getAppIcon(fallbackClass, "application-x-executable");
    }

    function isPinned(appId: string): bool {
        if (!appId)
            return false;
        const norm = normalizeId(appId);
        return GlobalConfig.dock.pinnedApps.some(id => normalizeId(id) === norm);
    }

    function togglePin(appId: string): void {
        if (!appId)
            return;
        const norm = normalizeId(appId);
        const current = [...GlobalConfig.dock.pinnedApps];
        if (current.some(id => normalizeId(id) === norm))
            GlobalConfig.dock.pinnedApps = current.filter(id => normalizeId(id) !== norm);
        else
            GlobalConfig.dock.pinnedApps = [...current, appId];
    }

    function launchEntry(entry: DesktopEntry): void {
        if (!entry)
            return;

        if (entry.runInTerminal) {
            Quickshell.execDetached({
                command: [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command],
                workingDirectory: entry.workingDirectory
            });
        } else {
            entry.execute();
        }
    }

    function focusWindowNoWarp(address: string): void {
        if (!address)
            return;

        const wasNoWarps = Boolean(Hypr.options["cursor:no_warps"] ?? false);
        if (wasNoWarps) {
            Hypr.focusWindow(address);
            return;
        }

        if (Hypr.usingLua) {
            Hypr.extras.batchMessage([
                "eval hl.config({ cursor = { no_warps = true } })",
                `dispatch hl.dsp.focus({ window = "address:0x${address}" })`,
                "eval hl.config({ cursor = { no_warps = false } })"
            ]);
        } else {
            Hypr.extras.batchMessage([
                "keyword cursor:no_warps 1",
                `dispatch focuswindow address:0x${address}`,
                "keyword cursor:no_warps 0"
            ]);
        }
    }

    function focusOrRestoreWindow(client: var): void {
        const address = cleanAddress(client);
        if (!address)
            return;

        if (isMinimized(client)) {
            const activeWorkspaceId = Number(Hypr.focusedMonitor?.lastIpcObject?.activeWorkspace?.id ?? 0);
            const workspace = Hypr.workspaces.values.find(w => w.id === activeWorkspaceId && w.id > 0)
                ?? Hypr.workspaces.values.find(w => w.id > 0 && w.monitor === Hypr.focusedMonitor?.name)
                ?? Hypr.workspaces.values.find(w => w.id > 0);
            const target = workspace?.id ?? 1;
            const winTarget = `address:0x${address}`;
            const wasNoWarps = Boolean(Hypr.options["cursor:no_warps"] ?? false);

            if (Hypr.usingLua) {
                const cmds = [
                    ...(wasNoWarps ? [] : ["eval hl.config({ cursor = { no_warps = true } })"]),
                    `dispatch hl.dsp.window.move({workspace=${target},follow=true,window="${winTarget}"})`,
                    `dispatch hl.dsp.focus({ window = "${winTarget}" })`,
                    ...(wasNoWarps ? [] : ["eval hl.config({ cursor = { no_warps = false } })"])
                ];
                Hypr.extras.batchMessage(cmds);
            } else {
                const cmds = [
                    ...(wasNoWarps ? [] : ["keyword cursor:no_warps 1"]),
                    `dispatch movetoworkspace ${target},${winTarget}`,
                    `dispatch focuswindow ${winTarget}`,
                    ...(wasNoWarps ? [] : ["keyword cursor:no_warps 0"])
                ];
                Hypr.extras.batchMessage(cmds);
            }
        } else {
            focusWindowNoWarp(address);
        }
    }

    function minimizeWindow(client: var): void {
        const address = cleanAddress(client);
        if (!address)
            return;

        const target = `address:0x${address}`;
        Hypr.dispatch(Hypr.usingLua
            ? `hl.dsp.window.move({workspace="special:minimized",follow=false,window="${target}"})`
            : `movetoworkspacesilent special:minimized,${target}`);
    }

    function closeWindow(client: var): void {
        const address = cleanAddress(client);
        if (!address)
            return;

        const target = `address:0x${address}`;
        Hypr.dispatch(Hypr.usingLua
            ? `hl.dsp.window.close({window="${target}"})`
            : `closewindow ${target}`);
    }

    // Builds grouped dock items (pinned apps first, then unpinned running apps)
    function buildItems(monitor: var, perMonitor: bool): var {
        void root.revision;
        void GlobalConfig.dock.pinnedApps;
        void root.activeAddress;
        const groups = new Map();
        const pinnedOrder = [];

        for (const rawId of GlobalConfig.dock.pinnedApps) {
            const entry = entryForId(rawId);
            const appId = entry?.id ?? rawId;
            const key = `entry:${normalizeId(appId)}`;
            if (groups.has(key))
                continue;

            const item = {
                key: key,
                appId: appId,
                entry: entry,
                name: entry?.name ?? rawId,
                icon: iconSource(entry, rawId),
                pinned: true,
                windows: [],
                focused: false,
                minimizedOnly: false
            };
            groups.set(key, item);
            pinnedOrder.push(item);
        }

        const monitorName = monitor?.name ?? "";
        const monitorId = monitor?.id ?? -1;
        const ignoredTags = GlobalConfig.bar.workspaces.ignoredTags;
        const unpinnedOrder = [];

        for (const t of Hypr.toplevels.values) {
            if (Hypr.isToplevelIgnored(t, ignoredTags))
                continue;

            if (perMonitor && monitor) {
                const winMonName = t.monitor?.name ?? t.workspace?.monitor?.name ?? "";
                const winMonId = t.lastIpcObject?.monitor ?? -1;
                if (winMonName !== monitorName && winMonId !== monitorId)
                    continue;
            }

            const ipc = t.lastIpcObject;
            const cls = String(ipc?.class || ipc?.initialClass || "");
            const entry = entryForWindow(t);
            const appId = entry?.id ?? "";
            const key = entry ? `entry:${normalizeId(entry.id)}` : `class:${cls.toLowerCase()}`;

            let group = groups.get(key);
            if (!group) {
                group = {
                    key: key,
                    appId: appId,
                    entry: entry,
                    name: entry?.name ?? (cls || (ipc?.title ?? Tr.tr("Application"))),
                    icon: iconSource(entry, cls),
                    pinned: false,
                    windows: [],
                    focused: false,
                    minimizedOnly: false
                };
                groups.set(key, group);
                unpinnedOrder.push(group);
            }

            group.windows.push(t);
            if (cleanAddress(t) === root.activeAddress)
                group.focused = true;
        }

        for (const group of groups.values()) {
            if (group.windows.length > 0) {
                group.windows.sort((a, b) => {
                    const wa = a.lastIpcObject?.workspace?.id ?? 0;
                    const wb = b.lastIpcObject?.workspace?.id ?? 0;
                    if (wa !== wb)
                        return wa - wb;
                    return cleanAddress(a).localeCompare(cleanAddress(b));
                });
                group.minimizedOnly = group.windows.every(w => isMinimized(w));
            }
        }

        unpinnedOrder.sort((a, b) => a.name.localeCompare(b.name) || a.key.localeCompare(b.key));
        return [...pinnedOrder, ...unpinnedOrder];
    }

    Timer {
        id: refreshTimer

        interval: 25
        repeat: false
        onTriggered: root.revision++
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;
            if (n.includes("window") || n.includes("workspace") || ["minimize", "fullscreen", "pin", "activespecial", "focusedmon"].includes(n))
                refreshTimer.restart();
        }

        target: Hyprland
    }

    Connections {
        function onValuesChanged(): void {
            refreshTimer.restart();
        }

        target: DesktopEntries.applications
    }

    IpcHandler {
        function toggle(): void {
            GlobalConfig.dock.enabled = !GlobalConfig.dock.enabled;
        }

        function show(): void {
            GlobalConfig.dock.enabled = true;
        }

        function hide(): void {
            GlobalConfig.dock.enabled = false;
        }

        target: "dock"
    }
}
