pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services

// Context menu shown above a right-clicked dock icon without cross-tree reparenting.
Item {
    id: root

    required property var targetItem
    required property real anchorCenterX
    required property bool open

    readonly property var activeItem: targetItem ?? displayedItem
    readonly property var windows: activeItem?.windows ?? []
    readonly property int windowCount: windows.length
    readonly property bool hasWindows: windowCount > 0
    readonly property bool minimizedOnly: activeItem?.minimizedOnly ?? false
    readonly property bool isPinned: activeItem?.pinned ?? false
    readonly property bool canLaunch: (activeItem?.entry ?? null) !== null
    readonly property bool canPin: String(activeItem?.appId || "").length > 0

    readonly property real screenMargin: Tokens.padding.medium
    readonly property real panelsWidth: parent?.parent?.width ?? 1920
    readonly property real dockX: parent?.x ?? 0

    readonly property var actions: {
        if (!activeItem)
            return [];

        const list = [];
        if (canLaunch) {
            list.push({
                id: "launch",
                icon: "open_in_new",
                text: hasWindows ? Tr.tr("New window") : Tr.tr("Open"),
                divider: false,
                desktopAction: null,
                iconSource: ""
            });
        }

        const rawDesktopActions = activeItem.entry?.actions ?? [];
        let addedDesktopActions = 0;
        for (const act of rawDesktopActions) {
            if (!act || !act.name || addedDesktopActions >= 6)
                continue;
            const resolvedIcon = act.icon ? (Quickshell.iconPath(act.icon, true) || "") : "";
            list.push({
                id: `desktop:${act.id || addedDesktopActions}`,
                icon: resolvedIcon ? "" : "bolt",
                iconSource: resolvedIcon,
                text: act.name,
                divider: false,
                desktopAction: act
            });
            addedDesktopActions++;
        }

        const hasLowerActions = hasWindows || canPin;
        if (addedDesktopActions > 0 && hasLowerActions) {
            list.push({
                id: "divider",
                icon: "",
                iconSource: "",
                text: "",
                divider: true,
                desktopAction: null
            });
        }

        if (hasWindows) {
            list.push({
                id: "minimize",
                icon: minimizedOnly ? "open_in_full" : "minimize",
                iconSource: "",
                text: minimizedOnly ? Tr.tr("Restore") : (windowCount > 1 ? Tr.tr("Minimize all") : Tr.tr("Minimize")),
                divider: false,
                desktopAction: null
            });
        }
        if (canPin) {
            list.push({
                id: "pin",
                icon: isPinned ? "keep_off" : "keep",
                iconSource: "",
                text: isPinned ? Tr.tr("Unpin from dock") : Tr.tr("Pin to dock"),
                divider: false,
                desktopAction: null
            });
        }
        if (hasWindows) {
            list.push({
                id: "close",
                icon: "close",
                iconSource: "",
                text: windowCount > 1 ? Tr.tr("Close all") : Tr.tr("Close"),
                divider: false,
                desktopAction: null
            });
        }
        return list;
    }

    property var displayedItem: null

    signal actionTriggered(string actionId, var appData)
    signal desktopActionTriggered(var desktopAction, var appData)
    signal closeRequested

    visible: opacity > 0 && activeItem !== null
    opacity: open && targetItem !== null && actions.length > 0 ? 1 : 0
    implicitWidth: Math.max(176, Math.min(280, menuCol.implicitWidth + Tokens.padding.extraSmall * 2))
    implicitHeight: menuCol.implicitHeight + Tokens.padding.extraSmall * 2

    x: Math.max(-dockX + screenMargin, Math.min(panelsWidth - dockX - width - screenMargin, anchorCenterX - width / 2))

    onTargetItemChanged: {
        if (targetItem)
            displayedItem = targetItem;
    }

    onOpenChanged: {
        if (open && targetItem)
            displayedItem = targetItem;
    }

    onVisibleChanged: {
        if (!visible && !open)
            displayedItem = null;
    }

    transform: Scale {
        yScale: root.open ? 1 : 0.85
        xScale: root.open ? 1 : 0.95
        origin.x: root.width / 2
        origin.y: root.height

        Behavior on yScale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on xScale {
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

    Elevation {
        anchors.fill: bg
        radius: bg.radius
        level: 2
    }

    StyledRect {
        id: bg

        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerLow
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
    }

    ColumnLayout {
        id: menuCol

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        spacing: 0

        Repeater {
            id: actionRepeater

            model: root.actions

            delegate: Item {
                id: entryDelegate

                required property var modelData
                required property int index

                readonly property bool isDivider: modelData?.divider ?? false

                Layout.fillWidth: true
                implicitWidth: isDivider ? 0 : rowItem.implicitWidth
                implicitHeight: isDivider ? (Tokens.spacing.extraSmall * 2 + 1) : rowItem.implicitHeight

                StyledRect {
                    visible: entryDelegate.isDivider
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.padding.small
                    height: 1
                    radius: 1
                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
                }

                StyledRect {
                    id: rowItem

                    readonly property int itemPadding: Tokens.padding.small

                    visible: !entryDelegate.isDivider
                    anchors.fill: parent
                    implicitWidth: rowLayout.implicitWidth + itemPadding * 2
                    implicitHeight: rowLayout.implicitHeight + itemPadding * 2

                    radius: Tokens.rounding.extraSmall
                    topLeftRadius: entryDelegate.index === 0 ? Tokens.rounding.medium : radius
                    topRightRadius: entryDelegate.index === 0 ? Tokens.rounding.medium : radius
                    bottomLeftRadius: entryDelegate.index === actionRepeater.count - 1 ? Tokens.rounding.medium : radius
                    bottomRightRadius: entryDelegate.index === actionRepeater.count - 1 ? Tokens.rounding.medium : radius
                    color: "transparent"

                    StateLayer {
                        topLeftRadius: parent.topLeftRadius
                        topRightRadius: parent.topRightRadius
                        bottomLeftRadius: parent.bottomLeftRadius
                        bottomRightRadius: parent.bottomRightRadius
                        color: Colours.palette.m3onSurface
                        disabled: !root.open || entryDelegate.isDivider
                        onClicked: {
                            if (entryDelegate.modelData?.desktopAction)
                                root.desktopActionTriggered(entryDelegate.modelData.desktopAction, root.targetItem);
                            else
                                root.actionTriggered(entryDelegate.modelData.id, root.targetItem);
                            root.closeRequested();
                        }
                    }

                    RowLayout {
                        id: rowLayout

                        anchors.fill: parent
                        anchors.margins: rowItem.itemPadding
                        spacing: Tokens.spacing.small

                        IconImage {
                            visible: (entryDelegate.modelData?.iconSource ?? "").length > 0
                            Layout.alignment: Qt.AlignVCenter
                            asynchronous: true
                            implicitSize: 16
                            source: entryDelegate.modelData?.iconSource ?? ""
                        }

                        MaterialIcon {
                            visible: (entryDelegate.modelData?.iconSource ?? "").length === 0
                            Layout.alignment: Qt.AlignVCenter
                            text: entryDelegate.modelData?.icon ?? ""
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            text: entryDelegate.modelData?.text ?? ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
