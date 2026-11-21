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
    readonly property int pinnedCount: dockItems.filter(d => d.pinned).length
    readonly property bool hasPinnedItems: pinnedCount > 0

    readonly property int visibilityMode: Config.dock.visibility
    readonly property bool magnificationMode: Config.dock.hoverEffect === DockHoverEffect.Magnification
    readonly property real previewGap: Tokens.padding.small
    readonly property real maxDockWidth: Math.max(160, (parent?.width ?? screen?.width ?? 1920) - Tokens.padding.extraLarge * 4)
    readonly property real contentFullWidth: iconsRow.implicitWidth + Tokens.padding.large * 2
    readonly property bool overflowing: contentFullWidth > maxDockWidth
    readonly property real topHeadroom: Math.round(Config.dock.iconSize * 0.65) + 12

    readonly property bool launcherBlocking: (screenState?.launcher ?? false) && Config.launcher.edge === PanelEdge.Bottom
    readonly property bool sessionBlocking: (screenState?.session ?? false) && Config.session.enabled
    readonly property bool enabledOnScreen: Config.dock.enabled && !disabledScreen && !ShellState.sessionLocked && !fullscreen && !(screenState?.overview ?? false) && !launcherBlocking && !sessionBlocking && dockItems.length > 0
    readonly property bool reserveSpace: enabledOnScreen && visibilityMode === DockVisibility.AlwaysShow

    readonly property bool dockOccluded: {
        void DockService.revision;
        void Hypr.layoutRevision;
        if (visibilityMode !== DockVisibility.DodgeWindows || !enabledOnScreen || !monitor)
            return false;

        const monIpc = monitor.lastIpcObject;
        const hasMonDims = !!(monIpc && monIpc.width && monIpc.height);
        const scale = hasMonDims && monIpc.scale > 0 ? monIpc.scale : 1;
        const rotated = hasMonDims && (monIpc.transform ?? 0) % 2 === 1;
        const monW = hasMonDims ? (rotated ? monIpc.height : monIpc.width) / scale : (screen?.width ?? 0);
        const monH = hasMonDims ? (rotated ? monIpc.width : monIpc.height) / scale : (screen?.height ?? 0);
        if (monW <= 0 || monH <= 0)
            return false;
        const monX = monIpc?.x ?? 0;
        const monY = monIpc?.y ?? 0;

        const pillW = Math.max(120, root.width);
        const pillH = Math.max(48, root.height);
        const dockLeft = monX + (monW - pillW) / 2;
        const dockRight = dockLeft + pillW;
        const dockTop = monY + monH - bar.insetBottom - pillH;
        const dockBottom = monY + monH;

        const specialName = String(monIpc?.specialWorkspace?.name || "");
        const fallbackWsId = monIpc?.activeWorkspace?.id ?? 0;
        const ws = specialName ? Hypr.workspaces.values.find(w => w.name === specialName) : (monitor.activeWorkspace ?? (fallbackWsId > 0 ? Hypr.workspaces.values.find(w => w.id === fallbackWsId) : Hypr.focusedWorkspace));
        if (!ws)
            return false;

        for (const t of ws.toplevels.values) {
            const ipc = t?.lastIpcObject;
            if (!ipc || !ipc.mapped)
                continue;
            if (DockService.isMinimized(t))
                continue;
            if ((ipc.fullscreen ?? 0) > 0)
                return true;
            if (!ipc.size || !ipc.at)
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
    readonly property bool dragActive: dragKey !== "" && dragSourceIndex >= 0
    readonly property bool menuOpen: enabledOnScreen && dockShown && menuTargetItem !== null && !dragActive
    readonly property bool previewOpen: enabledOnScreen && dockShown && previewTargetItem !== null && !menuOpen && !dragActive
    readonly property bool pinnedPreviewOpen: pinnedPreviewKey !== ""
    readonly property alias previewItem: preview
    readonly property alias menuItem: contextMenu
    readonly property bool anyInteractionActive: dockHover.hovered || edgeHovered || preview.pointerInside || pinnedPreviewOpen || menuOpen || dragActive

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

    property string dragKey: ""
    property string dragAppId: ""
    property int dragSourceIndex: -1
    property int dragTargetIndex: -1
    property real dragStartX: 0
    property real dragOffsetX: 0
    property real dragSlotStep: 0

    property string launchPulseKey: ""
    property int launchPulseSeq: 0

    function anchorXForItem(itemRef: var): real {
        return dockFlickable.x + iconsRow.x + itemRef.slotCenterInRow - dockFlickable.contentX;
    }

    function triggerLaunchPulse(key: string): void {
        if (!key)
            return;
        launchPulseKey = key;
        launchPulseSeq++;
    }

    function beginDrag(itemRef: var, startX: real, currentX: real): void {
        closeAllPopups();
        dragKey = itemRef.modelData?.key ?? "";
        dragAppId = itemRef.modelData?.appId ?? "";
        dragSourceIndex = itemRef.index;
        dragTargetIndex = itemRef.index;
        dragStartX = startX;
        dragSlotStep = itemRef.baseSlotWidth + iconsRow.spacing;
        updateDrag(currentX);
    }

    function updateDrag(currentX: real): void {
        if (!dragActive)
            return;
        const step = Math.max(1, dragSlotStep);
        const minOffset = -dragSourceIndex * step;
        const maxOffset = Math.max(0, (pinnedCount - 1 - dragSourceIndex) * step);
        dragOffsetX = Math.max(minOffset, Math.min(maxOffset, currentX - dragStartX));
        dragTargetIndex = Math.max(0, Math.min(pinnedCount - 1, Math.round(dragSourceIndex + dragOffsetX / step)));
    }

    function endDrag(currentX: real, commit: bool): void {
        if (!dragActive)
            return;
        if (commit)
            updateDrag(currentX);

        const appId = dragAppId;
        const fromIdx = dragSourceIndex;
        const toIdx = dragTargetIndex;

        dragKey = "";
        dragAppId = "";
        dragSourceIndex = -1;
        dragTargetIndex = -1;
        dragOffsetX = 0;

        if (commit && appId && toIdx >= 0 && toIdx !== fromIdx)
            DockService.movePinnedToIndex(appId, toIdx);
    }

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

    visible: offsetScale < 1
    x: (parent.width - width) / 2
    y: parent.height - height + (height + 5) * offsetScale
    implicitWidth: Math.min(maxDockWidth, contentFullWidth)
    implicitHeight: iconsRow.implicitHeight + Tokens.padding.small + Tokens.padding.extraSmall
    opacity: 1 - offsetScale

    onEnabledOnScreenChanged: {
        if (!enabledOnScreen) {
            edgeReveal = false;
            edgeHovered = false;
            endDrag(0, false);
            closeAllPopups();
        }
    }

    onOverflowingChanged: {
        if (!overflowing)
            dockFlickable.contentX = 0;
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
        if (dragActive && !dockItems.some(d => d.key === dragKey && d.pinned))
            endDrag(0, false);

        const maxX = Math.max(0, dockFlickable.contentWidth - dockFlickable.width);
        if (dockFlickable.contentX > maxX)
            dockFlickable.contentX = maxX;
    }

    onAnyInteractionActiveChanged: {
        if (anyInteractionActive)
            autoHideTimer.stop();
        else if (edgeReveal)
            autoHideTimer.restart();
    }

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
            if (root.pendingHoverKey && !root.pinnedPreviewKey && !root.menuKey && !root.dragActive) {
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

    Flickable {
        id: dockFlickable

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.topMargin: -root.topHeadroom

        contentWidth: iconsRow.implicitWidth
        contentHeight: height
        clip: root.overflowing
        interactive: root.overflowing && !root.dragActive && !root.previewOpen && !root.menuOpen
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        WheelHandler {
            enabled: root.overflowing && !root.previewOpen && !root.menuOpen
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const rawDelta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y) ? event.angleDelta.x : event.angleDelta.y;
                if (rawDelta === 0)
                    return;
                const maxX = Math.max(0, dockFlickable.contentWidth - dockFlickable.width);
                dockFlickable.contentX = Math.max(0, Math.min(maxX, dockFlickable.contentX - rawDelta * 0.5));
                event.accepted = true;
            }
        }

        Row {
            id: iconsRow

            x: Math.max(0, (dockFlickable.width - implicitWidth) / 2)
            y: root.topHeadroom + Tokens.padding.small
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
                    readonly property bool isThisDragged: root.dragActive && root.dragKey === (dockIcon.modelData?.key ?? "")

                    iconSize: Config.dock.iconSize
                    magnificationMode: root.magnificationMode
                    pointerX: root.rowPointerX
                    pointerActive: root.rowPointerActive && !root.dragActive
                    showDividerBefore: firstUnpinned
                    isPreviewTarget: (root.previewOpen && root.previewTargetItem?.key === dockIcon.modelData?.key) || (root.menuOpen && root.menuTargetItem?.key === dockIcon.modelData?.key)
                    canDragReorder: dockIcon.isPinned && root.pinnedCount > 1
                    isDragged: isThisDragged
                    dragOffsetX: isThisDragged ? root.dragOffsetX : 0
                    dragShiftX: {
                        if (!root.dragActive || !dockIcon.isPinned || dockIcon.index === root.dragSourceIndex)
                            return 0;
                        if (root.dragSourceIndex < root.dragTargetIndex && dockIcon.index > root.dragSourceIndex && dockIcon.index <= root.dragTargetIndex)
                            return -root.dragSlotStep;
                        if (root.dragSourceIndex > root.dragTargetIndex && dockIcon.index >= root.dragTargetIndex && dockIcon.index < root.dragSourceIndex)
                            return root.dragSlotStep;
                        return 0;
                    }
                    externalLaunchSeq: root.launchPulseKey === (dockIcon.modelData?.key ?? "") ? root.launchPulseSeq : 0

                    onPointerMoved: rowX => {
                        if (!root.dragActive) {
                            root.rowPointerX = rowX;
                            root.rowPointerActive = true;
                        }
                    }

                    onHoverEntered: (itemRef, appData) => {
                        hoverCloseTimer.stop();
                        if (root.menuKey !== "" || root.pinnedPreviewKey !== "" || root.dragActive)
                            return;

                        const centerX = root.anchorXForItem(itemRef);
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
                        const centerX = root.anchorXForItem(itemRef);
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
                        root.menuAnchorX = root.anchorXForItem(itemRef);
                        root.menuKey = appData.key;
                    }

                    onMiddleClickLaunched: root.closeAllPopups()
                    onDragStarted: (itemRef, startX, currentX) => root.beginDrag(itemRef, startX, currentX)
                    onDragMoved: (itemRef, currentX) => root.updateDrag(currentX)
                    onDragFinished: (itemRef, currentX) => root.endDrag(currentX, true)
                    onDragCanceled: root.endDrag(0, false)
                }
            }
        }
    }

    // Subtle scroll arrows at left/right edges when the dock overflows the monitor width
    MaterialIcon {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: "chevron_left"
        color: Colours.palette.m3onSurfaceVariant
        opacity: root.overflowing && dockFlickable.contentX > 2 ? 0.85 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }
    }

    MaterialIcon {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: "chevron_right"
        color: Colours.palette.m3onSurfaceVariant
        opacity: root.overflowing && dockFlickable.contentX < dockFlickable.contentWidth - dockFlickable.width - 2 ? 0.85 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
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
                root.triggerLaunchPulse(appData.key);
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

        onDesktopActionTriggered: (desktopAction, appData) => {
            if (!appData || !desktopAction)
                return;
            root.triggerLaunchPulse(appData.key);
            DockService.launchAction(desktopAction, appData.entry);
        }

        onCloseRequested: root.closeAllPopups()
    }
}
