pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar as Bar

// Border-integrated bottom application dock hosted inside Drawers/Panels so its
// surface and corners melt seamlessly into the Caelestia screen border via BlobGroup.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property bool fullscreen

    readonly property HyprlandMonitor monitor: screen ? Hypr.monitorFor(screen) : null
    readonly property bool disabledScreen: screen ? Strings.testRegexList(GlobalConfig.dock.excludedScreens, screen.name) : true
    readonly property var dockItems: DockService.buildItems(monitor, Config.dock.perMonitorWindows)
    readonly property bool hasPinnedItems: dockItems.some(d => d.pinned)

    readonly property int visibilityMode: Config.dock.visibility
    readonly property bool magnificationMode: Config.dock.hoverEffect === DockHoverEffect.Magnification
    readonly property real previewGap: Tokens.padding.small

    readonly property bool launcherBlocking: (screenState?.launcher ?? false) && Config.launcher.edge === PanelEdge.Bottom
    readonly property bool sessionBlocking: (screenState?.session ?? false) && Config.session.enabled
    readonly property bool enabledOnScreen: Config.dock.enabled && !disabledScreen && !ShellState.sessionLocked && !fullscreen && !(screenState?.overview ?? false) && !launcherBlocking && !sessionBlocking && dockItems.length > 0
    readonly property bool reserveSpace: enabledOnScreen && visibilityMode === DockVisibility.AlwaysShow

    readonly property bool dockOccluded: {
        void DockService.revision;
        if (visibilityMode !== DockVisibility.DodgeWindows || !enabledOnScreen || !monitor)
            return false;

        const monIpc = monitor.lastIpcObject;
        if (!monIpc || !monIpc.width || !monIpc.height)
            return false;

        const scale = monIpc.scale > 0 ? monIpc.scale : 1;
        const rotated = (monIpc.transform ?? 0) % 2 === 1;
        const monW = (rotated ? monIpc.height : monIpc.width) / scale;
        const monH = (rotated ? monIpc.width : monIpc.height) / scale;
        const monX = monIpc.x ?? 0;
        const monY = monIpc.y ?? 0;

        const pillW = Math.max(120, root.width);
        const pillH = Math.max(48, root.height);
        const dockLeft = monX + (monW - pillW) / 2;
        const dockRight = dockLeft + pillW;
        const dockTop = monY + monH - bar.insetBottom - pillH;
        const dockBottom = monY + monH;

        const specialName = String(monIpc.specialWorkspace?.name || "");
        const ws = specialName ? Hypr.workspaces.values.find(w => w.name === specialName) : monitor.activeWorkspace;
        if (!ws)
            return false;

        for (const t of ws.toplevels.values) {
            const ipc = t?.lastIpcObject;
            if (!ipc || !ipc.mapped || !ipc.size || !ipc.at)
                continue;
            if (DockService.isMinimized(t))
                continue;

            const wx1 = ipc.at[0];
            const wy1 = ipc.at[1];
            const wx2 = wx1 + ipc.size[0];
            const wy2 = wy1 + ipc.size[1];

            if (wx2 > dockLeft && wx1 < dockRight && wy2 > dockTop && wy1 < dockBottom)
                return true;
        }
        return false;
    }

    readonly property var previewTargetItem: {
        const key = pinnedPreviewKey || hoveredKey;
        if (!key)
            return null;
        return dockItems.find(d => d.key === key) ?? null;
    }
    readonly property var menuTargetItem: {
        if (!menuKey)
            return null;
        return dockItems.find(d => d.key === menuKey) ?? null;
    }
    readonly property bool menuOpen: enabledOnScreen && dockShown && menuTargetItem !== null
    readonly property bool previewOpen: enabledOnScreen && dockShown && previewTargetItem !== null && !menuOpen
    readonly property bool pinnedPreviewOpen: pinnedPreviewKey !== ""
    readonly property alias previewItem: preview
    readonly property alias menuItem: contextMenu
    readonly property bool anyInteractionActive: dockHover.hovered || edgeHovered || preview.pointerInside || pinnedPreviewOpen || menuOpen

    readonly property bool dockShown: {
        if (!enabledOnScreen)
            return false;
        if (visibilityMode === DockVisibility.AlwaysShow || visibilityMode === DockVisibility.Floating)
            return true;
        if (visibilityMode === DockVisibility.AutoHide)
            return edgeReveal || anyInteractionActive;
        return !dockOccluded || edgeReveal || anyInteractionActive;
    }

    property bool edgeHovered: false
    property bool edgeReveal: false
    property string menuKey: ""
    property real menuAnchorX: width / 2
    property string hoveredKey: ""
    property string pendingHoverKey: ""
    property string pinnedPreviewKey: ""
    property real previewAnchorX: width / 2
    property real pendingPreviewAnchorX: width / 2
    property real offsetScale: dockShown ? 0 : 1
    property real rowPointerX: -1
    property bool rowPointerActive: false

    function pokeEdge(): void {
        if (!enabledOnScreen)
            return;
        autoHideTimer.stop();
        edgeReveal = true;
    }

    function closeAllPopups(): void {
        hoveredKey = "";
        pendingHoverKey = "";
        pinnedPreviewKey = "";
        menuKey = "";
        hoverPreviewTimer.stop();
        hoverCloseTimer.stop();
    }

    onEnabledOnScreenChanged: {
        if (!enabledOnScreen) {
            edgeReveal = false;
            edgeHovered = false;
            closeAllPopups();
        }
    }

    onPinnedPreviewKeyChanged: {
        if (pinnedPreviewKey && !dockItems.some(d => d.key === pinnedPreviewKey && d.windows.length > 1))
            pinnedPreviewKey = "";
    }

    onDockItemsChanged: {
        if (pinnedPreviewKey && !dockItems.some(d => d.key === pinnedPreviewKey && d.windows.length > 1))
            pinnedPreviewKey = "";
        if (hoveredKey && !dockItems.some(d => d.key === hoveredKey))
            hoveredKey = "";
        if (menuKey && !dockItems.some(d => d.key === menuKey))
            menuKey = "";
    }

    onAnyInteractionActiveChanged: {
        if (anyInteractionActive)
            autoHideTimer.stop();
        else if (edgeReveal)
            autoHideTimer.restart();
    }

    visible: offsetScale < 1
    x: (parent.width - width) / 2
    y: parent.height - height + (height + 5) * offsetScale
    implicitWidth: iconsRow.implicitWidth + Tokens.padding.large * 2
    implicitHeight: iconsRow.implicitHeight + Tokens.padding.small + Tokens.padding.extraSmall
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Timer {
        id: autoHideTimer

        interval: Math.max(80, Config.dock.hideDelay)
        repeat: false
        onTriggered: {
            if (!root.anyInteractionActive)
                root.edgeReveal = false;
        }
    }

    Timer {
        id: hoverPreviewTimer

        interval: Math.max(40, Config.dock.previewDelay)
        repeat: false
        onTriggered: {
            if (root.pendingHoverKey && !root.pinnedPreviewKey && !root.menuKey) {
                root.hoveredKey = root.pendingHoverKey;
                root.previewAnchorX = root.pendingPreviewAnchorX;
            }
        }
    }

    Timer {
        id: hoverCloseTimer

        interval: 150
        repeat: false
        onTriggered: {
            if (!dockHover.hovered && !preview.pointerInside && !root.pinnedPreviewKey)
                root.hoveredKey = "";
        }
    }

    HoverHandler {
        id: dockHover

        onHoveredChanged: {
            if (hovered) {
                hoverCloseTimer.stop();
                autoHideTimer.stop();
            } else {
                root.rowPointerActive = false;
                root.rowPointerX = -1;
                hoverPreviewTimer.stop();
                root.pendingHoverKey = "";
                hoverCloseTimer.restart();
            }
        }
    }

    Row {
        id: iconsRow

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.padding.small
        spacing: Tokens.spacing.extraSmall

        HoverHandler {
            id: rowHoverTracker

            onPointChanged: {
                if (hovered) {
                    root.rowPointerX = point.position.x;
                    root.rowPointerActive = true;
                }
            }
            onHoveredChanged: {
                if (hovered) {
                    root.rowPointerX = point.position.x;
                    root.rowPointerActive = true;
                } else {
                    root.rowPointerActive = false;
                    root.rowPointerX = -1;
                }
            }
        }

        Repeater {
            id: iconsRepeater

            model: ScriptModel {
                values: root.dockItems
                objectProp: "key"
            }

            delegate: DockItem {
                id: dockIcon

                readonly property bool firstUnpinned: dockIcon.index > 0 && root.hasPinnedItems && !(dockIcon.modelData?.pinned ?? false) && (root.dockItems[dockIcon.index - 1]?.pinned ?? false)

                iconSize: Config.dock.iconSize
                magnificationMode: root.magnificationMode
                pointerX: root.rowPointerX
                pointerActive: root.rowPointerActive
                showDividerBefore: firstUnpinned
                isPreviewTarget: (root.previewOpen && root.previewTargetItem?.key === dockIcon.modelData?.key) || (root.menuOpen && root.menuTargetItem?.key === dockIcon.modelData?.key)

                onHoverEntered: (itemRef, appData) => {
                    hoverCloseTimer.stop();
                    if (root.menuKey !== "" || root.pinnedPreviewKey !== "")
                        return;

                    const centerX = iconsRow.x + itemRef.slotCenterInRow;
                    root.pendingHoverKey = appData.key;
                    root.pendingPreviewAnchorX = centerX;

                    if (root.hoveredKey !== "") {
                        root.hoveredKey = appData.key;
                        root.previewAnchorX = centerX;
                    } else {
                        hoverPreviewTimer.restart();
                    }
                }

                onHoverExited: itemRef => {
                    if (root.pendingHoverKey === itemRef.modelData?.key) {
                        root.pendingHoverKey = "";
                        hoverPreviewTimer.stop();
                    }
                    hoverCloseTimer.restart();
                }

                onMultiWindowClicked: (itemRef, appData) => {
                    root.menuKey = "";
                    if (root.pinnedPreviewKey === appData.key) {
                        root.pinnedPreviewKey = "";
                        return;
                    }
                    const centerX = iconsRow.x + itemRef.slotCenterInRow;
                    root.hoveredKey = "";
                    root.previewAnchorX = centerX;
                    root.pinnedPreviewKey = appData.key;
                }

                onContextMenuRequested: (itemRef, appData) => {
                    hoverPreviewTimer.stop();
                    root.hoveredKey = "";
                    root.pinnedPreviewKey = "";
                    if (root.menuKey === appData.key) {
                        root.menuKey = "";
                        return;
                    }
                    root.menuAnchorX = iconsRow.x + itemRef.slotCenterInRow;
                    root.menuKey = appData.key;
                }
            }
        }
    }

    DockPreview {
        id: preview

        screen: root.screen
        targetItem: root.previewTargetItem
        anchorCenterX: root.previewAnchorX
        open: root.previewOpen
        pinnedMode: root.pinnedPreviewKey !== ""
        y: -height - root.previewGap

        onPointerInsideChanged: {
            if (pointerInside) {
                hoverCloseTimer.stop();
                autoHideTimer.stop();
            } else {
                hoverCloseTimer.restart();
            }
        }

        onWindowActivated: client => {
            DockService.focusOrRestoreWindow(client);
            root.closeAllPopups();
        }

        onWindowClosed: client => {
            DockService.closeWindow(client);
        }

        onCloseRequested: root.closeAllPopups()
    }

    DockContextMenu {
        id: contextMenu

        targetItem: root.menuTargetItem
        anchorCenterX: root.menuAnchorX
        open: root.menuOpen
        y: -height - root.previewGap

        onActionTriggered: (actionId, appData) => {
            if (!appData)
                return;

            if (actionId === "launch" && appData.entry) {
                DockService.launchEntry(appData.entry);
            } else if (actionId === "minimize") {
                const wins = appData.windows ?? [];
                if (appData.minimizedOnly) {
                    for (const w of wins)
                        DockService.focusOrRestoreWindow(w);
                } else {
                    for (const w of wins)
                        DockService.minimizeWindow(w);
                }
            } else if (actionId === "pin" && appData.appId) {
                DockService.togglePin(appData.appId);
            } else if (actionId === "close") {
                for (const w of appData.windows ?? [])
                    DockService.closeWindow(w);
            }
        }

        onCloseRequested: root.closeAllPopups()
    }
}
