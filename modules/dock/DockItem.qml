pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

// Single grouped application item inside the dock bar.
Item {
    id: root

    required property var modelData
    required property int index
    required property real iconSize
    required property bool magnificationMode
    required property real pointerX
    required property bool pointerActive
    required property bool showDividerBefore
    required property bool isPreviewTarget
    required property bool canDragReorder
    required property bool isDragged
    required property real dragOffsetX
    required property real dragShiftX
    required property int externalLaunchSeq

    readonly property var windows: modelData?.windows ?? []
    readonly property int windowCount: windows.length
    readonly property bool hasWindows: windowCount > 0
    readonly property bool isFocused: modelData?.focused ?? false
    readonly property bool minimizedOnly: modelData?.minimizedOnly ?? false
    readonly property bool isPinned: modelData?.pinned ?? false
    readonly property bool canLaunch: (modelData?.entry ?? null) !== null
    readonly property bool canPin: String(modelData?.appId || "").length > 0
    readonly property int notifCount: modelData?.notifCount ?? 0
    readonly property bool hovered: itemMouse.containsMouse

    // Magnification math (macOS-style smooth cosine falloff around pointerX)
    readonly property real baseSlotWidth: iconSize + Tokens.padding.small * 2
    readonly property real dividerWidth: showDividerBefore ? (Tokens.spacing.small * 2 + 1) : 0
    readonly property real itemCenterX: x + dividerWidth + baseSlotWidth / 2
    readonly property real magDist: Math.abs(pointerX - itemCenterX)
    readonly property real magRadius: Math.max(80, iconSize * 2.4)
    readonly property real rawMagInfluence: magnificationMode && pointerActive && !isDragged && magDist < magRadius ? Math.cos((magDist / magRadius) * (Math.PI / 2)) : 0
    readonly property real magInfluence: magnificationMode && !isDragged ? Math.max(rawMagInfluence, hovered ? 1.0 : 0) : 0
    readonly property real effectiveScale: {
        if (isDragged)
            return 1.12;
        if (magnificationMode)
            return 1 + 0.36 * magInfluence;
        if (itemMouse.pressed)
            return 0.92;
        return hovered ? 1.06 : 1.0;
    }
    readonly property real slotCenterInRow: x + dividerWidth + iconSlot.width / 2

    property real liftOffset: {
        if (isDragged)
            return -6;
        if (magnificationMode)
            return -iconSize * 0.22 * magInfluence;
        return hovered ? -1.5 : 0;
    }
    property real extraSlotWidth: magnificationMode ? (iconSize * 0.34 * magInfluence) : 0
    property bool launching: false
    property real launchBounceOffset: 0
    property int prevWindowCount: windowCount

    signal hoverEntered(var itemRef, var appData)
    signal hoverExited(var itemRef)
    signal pointerMoved(real rowX)
    signal multiWindowClicked(var itemRef, var appData)
    signal contextMenuRequested(var itemRef, var appData)
    signal middleClickLaunched(var itemRef, var appData)
    signal dragStarted(var itemRef, real startX, real currentX)
    signal dragMoved(var itemRef, real currentX)
    signal dragFinished(var itemRef, real currentX)
    signal dragCanceled(var itemRef)

    function startLaunchPulse(): void {
        launching = true;
        launchTimeout.restart();
    }

    z: isDragged ? 10 : 0
    implicitWidth: dividerWidth + iconSlot.width
    implicitHeight: iconSize + Tokens.padding.small * 2 + 8

    onWindowCountChanged: {
        if (windowCount > prevWindowCount && launching) {
            launching = false;
            launchTimeout.stop();
        }
        prevWindowCount = windowCount;
    }

    onExternalLaunchSeqChanged: {
        if (externalLaunchSeq > 0)
            startLaunchPulse();
    }

    onLaunchingChanged: {
        if (!launching)
            launchBounceOffset = 0;
    }

    Behavior on extraSlotWidth {
        enabled: root.magnificationMode

        Anim {
            duration: Tokens.anim.durations.small
            easing: Tokens.anim.expressiveFastSpatial
        }
    }

    Behavior on liftOffset {
        Anim {
            duration: Tokens.anim.durations.small
            easing: Tokens.anim.expressiveFastSpatial
        }
    }

    Behavior on launchBounceOffset {
        enabled: !launchBounceAnim.running

        Anim {
            type: Anim.FastSpatial
        }
    }

    Timer {
        id: launchTimeout

        interval: 2400
        repeat: false
        onTriggered: root.launching = false
    }

    SequentialAnimation {
        id: launchBounceAnim

        running: root.launching
        loops: Animation.Infinite

        Anim {
            target: root
            property: "launchBounceOffset"
            to: -Math.max(8, root.iconSize * 0.24)
            duration: 240
            easing: Tokens.anim.expressiveFastSpatial
        }

        Anim {
            target: root
            property: "launchBounceOffset"
            to: 0
            duration: 260
            easing: Tokens.anim.expressiveFastSpatial
        }

        PauseAnimation {
            duration: 140
        }
    }

    // Subtle divider separating pinned apps from unpinned running apps
    Item {
        id: dividerSpacer

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.dividerWidth
        height: root.iconSize * 0.65
        visible: root.showDividerBefore

        StyledRect {
            anchors.centerIn: parent
            width: 1
            height: parent.height
            radius: 1
            color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
        }
    }

    Item {
        id: iconSlot

        anchors.left: dividerSpacer.visible ? dividerSpacer.right : parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.baseSlotWidth + root.extraSlotWidth
        height: parent.height

        Item {
            id: iconVisuals

            anchors.fill: parent
            opacity: root.isDragged ? 0.9 : 1.0

            transform: Translate {
                x: root.isDragged ? root.dragOffsetX : root.dragShiftX

                Behavior on x {
                    enabled: !root.isDragged

                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            // Material highlight pill shown behind the icon in Highlight mode
            StyledRect {
                id: highlightBg

                readonly property bool isHoverHighlight: !root.magnificationMode && (root.hovered || root.isPreviewTarget || root.isDragged)
                readonly property bool isFocusHighlight: !root.magnificationMode && root.isFocused

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -3
                width: root.iconSize + Tokens.padding.small * 1.5
                height: root.iconSize + Tokens.padding.small * 1.2
                radius: Tokens.rounding.large
                visible: !root.magnificationMode
                color: isHoverHighlight ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest
                opacity: isHoverHighlight ? 0.85 : isFocusHighlight ? 0.42 : 0
                scale: isHoverHighlight ? (itemMouse.pressed ? 0.94 : 1.0) : 0.88

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on color {
                    CAnim {}
                }
            }

            Item {
                id: iconTransformContainer

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -3 + root.liftOffset + root.launchBounceOffset
                width: root.iconSize
                height: root.iconSize
                scale: root.effectiveScale
                transformOrigin: Item.Bottom

                Behavior on scale {
                    Anim {
                        duration: Tokens.anim.durations.small
                        easing: Tokens.anim.expressiveFastSpatial
                    }
                }

                IconImage {
                    id: appIcon

                    anchors.fill: parent
                    asynchronous: true
                    implicitSize: root.iconSize
                    opacity: root.minimizedOnly ? 0.65 : 1.0
                    source: root.modelData?.icon ?? ""

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                // Notification badge for active unread notifications belonging to this app
                StyledRect {
                    id: notifBadge

                    readonly property bool shown: root.notifCount > 0
                    readonly property string labelText: root.notifCount > 99 ? "99+" : String(root.notifCount)

                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -3
                    anchors.rightMargin: -4
                    implicitWidth: Math.max(implicitHeight, badgeText.implicitWidth + 8)
                    implicitHeight: Math.max(16, badgeText.implicitHeight + 2)
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3error
                    border.width: 1.5
                    border.color: Colours.tPalette.m3surface
                    opacity: shown ? 1 : 0
                    scale: shown ? 1 : 0.4
                    visible: opacity > 0.01

                    Behavior on opacity {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }

                    Behavior on scale {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    StyledText {
                        id: badgeText

                        anchors.centerIn: parent
                        text: notifBadge.labelText
                        color: Colours.palette.m3onError
                        font: Tokens.font.label.small
                    }
                }
            }

            // Running / focused / minimized indicator dots under the icon
            Row {
                id: indicatorRow

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                spacing: 3
                visible: root.hasWindows

                Repeater {
                    model: Math.min(3, root.windowCount)

                    delegate: StyledRect {
                        required property int index

                        readonly property bool primaryPill: index === 0 && root.isFocused

                        width: primaryPill ? 14 : (root.windowCount === 1 ? 7 : 5)
                        height: 4
                        radius: Tokens.rounding.full
                        color: {
                            if (root.isFocused && index === 0)
                                return Colours.palette.m3primary;
                            if (root.minimizedOnly)
                                return Colours.palette.m3outline;
                            return Colours.palette.m3onSurfaceVariant;
                        }

                        Behavior on width {
                            Anim {
                                type: Anim.FastEffects
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            id: itemMouse

            property real pressRowX: 0
            property bool didDrag: false
            property bool leftPressed: false
            property real lastWheelTime: 0

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            preventStealing: root.canDragReorder
            cursorShape: root.isDragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor

            onEntered: {
                if (!root.isDragged) {
                    root.pointerMoved(root.itemCenterX);
                    root.hoverEntered(root, root.modelData);
                }
            }
            onExited: {
                if (!root.isDragged)
                    root.hoverExited(root);
            }

            onPressed: event => {
                didDrag = false;
                leftPressed = event.button === Qt.LeftButton;
                if (leftPressed && root.canDragReorder)
                    pressRowX = mapToItem(root.parent, event.x, 0).x;
            }

            onPositionChanged: event => {
                const curX = mapToItem(root.parent, event.x, 0).x;
                if (!didDrag && !root.isDragged)
                    root.pointerMoved(curX);
                if (!leftPressed || !root.canDragReorder)
                    return;
                if (!didDrag && Math.abs(curX - pressRowX) >= 8) {
                    didDrag = true;
                    root.dragStarted(root, pressRowX, curX);
                } else if (didDrag) {
                    root.dragMoved(root, curX);
                }
            }

            onReleased: event => {
                if (didDrag) {
                    const curX = mapToItem(root.parent, event.x, 0).x;
                    root.dragFinished(root, curX);
                }
                leftPressed = false;
            }

            onCanceled: {
                if (didDrag)
                    root.dragCanceled(root);
                didDrag = false;
                leftPressed = false;
            }

            onClicked: event => {
                if (didDrag) {
                    didDrag = false;
                    return;
                }

                if (event.button === Qt.RightButton) {
                    root.hoverExited(root);
                    root.contextMenuRequested(root, root.modelData);
                    return;
                }

                if (event.button === Qt.MiddleButton) {
                    if (root.canLaunch) {
                        root.startLaunchPulse();
                        DockService.launchEntry(root.modelData.entry);
                        root.middleClickLaunched(root, root.modelData);
                    }
                    return;
                }

                if (root.windowCount === 0) {
                    if (root.canLaunch) {
                        root.startLaunchPulse();
                        DockService.launchEntry(root.modelData.entry);
                    }
                } else if (root.windowCount === 1) {
                    const win = root.windows[0];
                    if (DockService.isMinimized(win)) {
                        DockService.focusOrRestoreWindow(win);
                    } else if (root.isFocused) {
                        if (Config.dock.activeClickAction === DockActiveClickAction.Minimize)
                            DockService.minimizeWindow(win);
                    } else {
                        DockService.focusOrRestoreWindow(win);
                    }
                } else {
                    root.multiWindowClicked(root, root.modelData);
                }
            }

            onWheel: event => {
                if (root.windowCount > 1 && Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x) && event.angleDelta.y !== 0) {
                    const now = Date.now();
                    if (now - lastWheelTime >= 120) {
                        lastWheelTime = now;
                        DockService.cycleAppWindow(root.windows, event.angleDelta.y > 0 ? -1 : 1);
                    }
                    event.accepted = true;
                    return;
                }
                event.accepted = false;
            }
        }
    }
}
