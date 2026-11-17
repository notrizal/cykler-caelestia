pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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

    readonly property var windows: modelData?.windows ?? []
    readonly property int windowCount: windows.length
    readonly property bool hasWindows: windowCount > 0
    readonly property bool isFocused: modelData?.focused ?? false
    readonly property bool minimizedOnly: modelData?.minimizedOnly ?? false
    readonly property bool isPinned: modelData?.pinned ?? false
    readonly property bool canLaunch: (modelData?.entry ?? null) !== null
    readonly property bool canPin: String(modelData?.appId || "").length > 0
    readonly property bool hovered: itemMouse.containsMouse

    // Magnification math (macOS-style smooth cosine falloff around pointerX)
    readonly property real itemCenterX: x + (dividerSpacer.visible ? dividerSpacer.width : 0) + iconSlot.width / 2
    readonly property real magDist: Math.abs(pointerX - itemCenterX)
    readonly property real magRadius: Math.max(80, iconSize * 2.4)
    readonly property real magInfluence: magnificationMode && pointerActive && magDist < magRadius ? Math.cos((magDist / magRadius) * (Math.PI / 2)) : 0
    readonly property real effectiveScale: magnificationMode ? (1 + 0.36 * magInfluence) : (hovered ? 1.08 : 1.0)
    readonly property real baseSlotWidth: iconSize + Tokens.padding.small * 2
    readonly property real dividerWidth: showDividerBefore ? (Tokens.spacing.small * 2 + 1) : 0
    readonly property real slotCenterInRow: x + dividerWidth + iconSlot.width / 2

    property real liftOffset: magnificationMode ? (-iconSize * 0.22 * magInfluence) : (hovered ? -2 : 0)
    property real extraSlotWidth: magnificationMode ? (iconSize * 0.34 * magInfluence) : 0

    signal hoverEntered(var itemRef, var appData)
    signal hoverExited(var itemRef)
    signal multiWindowClicked(var itemRef, var appData)
    signal contextMenuRequested(var itemRef, var appData)

    implicitWidth: dividerWidth + iconSlot.width
    implicitHeight: iconSize + Tokens.padding.small * 2 + 8

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
            id: iconTransformContainer

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -3 + root.liftOffset
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

        MouseArea {
            id: itemMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            onEntered: root.hoverEntered(root, root.modelData)
            onExited: root.hoverExited(root)

            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    root.hoverExited(root);
                    root.contextMenuRequested(root, root.modelData);
                    return;
                }

                if (root.windowCount === 0) {
                    if (root.canLaunch)
                        DockService.launchEntry(root.modelData.entry);
                } else if (root.windowCount === 1) {
                    const win = root.windows[0];
                    if (DockService.isMinimized(win))
                        DockService.focusOrRestoreWindow(win);
                    else if (root.isFocused)
                        DockService.minimizeWindow(win);
                    else
                        DockService.focusOrRestoreWindow(win);
                } else {
                    root.multiWindowClicked(root, root.modelData);
                }
            }
        }
    }
}
