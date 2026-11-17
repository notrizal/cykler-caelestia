pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

    readonly property var windows: targetItem?.windows ?? []
    readonly property int windowCount: windows.length
    readonly property bool hasWindows: windowCount > 0
    readonly property bool minimizedOnly: targetItem?.minimizedOnly ?? false
    readonly property bool isPinned: targetItem?.pinned ?? false
    readonly property bool canLaunch: (targetItem?.entry ?? null) !== null
    readonly property bool canPin: String(targetItem?.appId || "").length > 0

    readonly property real screenMargin: Tokens.padding.medium
    readonly property real panelsWidth: parent?.parent?.width ?? 1920
    readonly property real dockX: parent?.x ?? 0

    readonly property var actions: {
        if (!targetItem)
            return [];

        const list = [];
        if (canLaunch) {
            list.push({
                id: "launch",
                icon: "open_in_new",
                text: hasWindows ? Tr.tr("New window") : Tr.tr("Open")
            });
        }
        if (hasWindows) {
            list.push({
                id: "minimize",
                icon: minimizedOnly ? "open_in_full" : "minimize",
                text: minimizedOnly ? Tr.tr("Restore") : (windowCount > 1 ? Tr.tr("Minimize all") : Tr.tr("Minimize"))
            });
        }
        if (canPin) {
            list.push({
                id: "pin",
                icon: isPinned ? "keep_off" : "keep",
                text: isPinned ? Tr.tr("Unpin from dock") : Tr.tr("Pin to dock")
            });
        }
        if (hasWindows) {
            list.push({
                id: "close",
                icon: "close",
                text: windowCount > 1 ? Tr.tr("Close all") : Tr.tr("Close")
            });
        }
        return list;
    }

    signal actionTriggered(string actionId, var appData)
    signal closeRequested

    visible: opacity > 0
    opacity: open && targetItem !== null && actions.length > 0 ? 1 : 0
    implicitWidth: Math.max(168, menuCol.implicitWidth + Tokens.padding.extraSmall * 2)
    implicitHeight: menuCol.implicitHeight + Tokens.padding.extraSmall * 2

    x: Math.max(-dockX + screenMargin, Math.min(panelsWidth - dockX - width - screenMargin, anchorCenterX - width / 2))

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

            delegate: StyledRect {
                id: rowItem

                required property var modelData
                required property int index

                readonly property int itemPadding: Tokens.padding.small

                Layout.fillWidth: true
                implicitWidth: rowLayout.implicitWidth + itemPadding * 2
                implicitHeight: rowLayout.implicitHeight + itemPadding * 2

                radius: Tokens.rounding.extraSmall
                topLeftRadius: index === 0 ? Tokens.rounding.medium : radius
                topRightRadius: index === 0 ? Tokens.rounding.medium : radius
                bottomLeftRadius: index === actionRepeater.count - 1 ? Tokens.rounding.medium : radius
                bottomRightRadius: index === actionRepeater.count - 1 ? Tokens.rounding.medium : radius
                color: "transparent"

                StateLayer {
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    color: Colours.palette.m3onSurface
                    disabled: !root.open
                    onClicked: {
                        root.actionTriggered(rowItem.modelData.id, root.targetItem);
                        root.closeRequested();
                    }
                }

                RowLayout {
                    id: rowLayout

                    anchors.fill: parent
                    anchors.margins: rowItem.itemPadding
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        text: rowItem.modelData?.icon ?? ""
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        text: rowItem.modelData?.text ?? ""
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                    }
                }
            }
        }
    }
}
