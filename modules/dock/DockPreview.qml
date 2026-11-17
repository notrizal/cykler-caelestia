pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// Floating preview card shown above a hovered (or multi-window-clicked) dock icon.
Item {
    id: root

    required property ShellScreen screen
    required property var targetItem
    required property real anchorCenterX
    required property bool open
    required property bool pinnedMode

    readonly property var windows: targetItem?.windows ?? []
    readonly property bool hasWindows: windows.length > 0
    readonly property bool pointerInside: popupHover.hovered || hoveredCardCount > 0
    readonly property real screenMargin: Tokens.padding.medium
    readonly property real cardPadding: Tokens.padding.medium
    readonly property real panelsWidth: parent?.parent?.width ?? screen.width
    readonly property real dockX: parent?.x ?? 0
    property int hoveredCardCount: 0

    signal windowActivated(var client)
    signal windowClosed(var client)
    signal closeRequested

    visible: opacity > 0
    opacity: open && targetItem !== null ? 1 : 0
    implicitWidth: Math.min(panelsWidth - screenMargin * 2, contentLoader.implicitWidth)
    implicitHeight: contentLoader.implicitHeight

    x: Math.max(-dockX + screenMargin, Math.min(panelsWidth - dockX - width - screenMargin, anchorCenterX - width / 2))

    transform: Translate {
        y: root.open ? 0 : 8

        Behavior on y {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on x {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    HoverHandler {
        id: popupHover
    }

    Elevation {
        anchors.fill: bg
        radius: bg.radius
        level: 3
    }

    StyledRect {
        id: bg

        anchors.fill: parent
        radius: root.hasWindows ? Tokens.rounding.extraLarge : Tokens.rounding.full
        color: Colours.tPalette.m3surface
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
    }

    // Invisible downward bridge to the dock icon so moving the cursor from icon to preview never leaves the mask
    Item {
        anchors.top: bg.bottom
        anchors.horizontalCenter: bg.horizontalCenter
        width: Math.min(parent.width, 160)
        height: Tokens.padding.medium
    }

    Loader {
        id: contentLoader

        anchors.centerIn: parent
        sourceComponent: root.hasWindows ? windowPreviewsComp : tooltipComp
    }

    Component {
        id: tooltipComp

        Item {
            implicitWidth: tooltipText.implicitWidth + Tokens.padding.large * 2
            implicitHeight: tooltipText.implicitHeight + Tokens.padding.small * 2

            StyledText {
                id: tooltipText

                anchors.centerIn: parent
                text: root.targetItem?.name ?? ""
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.medium
            }
        }
    }

    Component {
        id: windowPreviewsComp

        Item {
            id: previewRoot

            readonly property int cardSpacing: Tokens.spacing.medium
            readonly property real maxWidth: Math.max(240, root.screen.width - root.screenMargin * 2 - root.cardPadding * 2)

            implicitWidth: Math.min(maxWidth, cardsRow.implicitWidth) + root.cardPadding * 2
            implicitHeight: cardsRow.implicitHeight + root.cardPadding * 2

            Flickable {
                anchors.fill: parent
                anchors.margins: root.cardPadding
                contentWidth: cardsRow.implicitWidth
                contentHeight: cardsRow.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: cardsRow

                    spacing: previewRoot.cardSpacing

                    Repeater {
                        model: ScriptModel {
                            values: root.windows
                        }

                        delegate: StyledRect {
                            id: card

                            required property var modelData

                            readonly property var ipc: modelData?.lastIpcObject
                            readonly property var ipcSize: ipc?.size ?? []
                            readonly property real winAspect: ipcSize.length === 2 && Number(ipcSize[1]) > 0 && Number(ipcSize[0]) > 0 ? Number(ipcSize[0]) / Number(ipcSize[1]) : 16 / 9
                            readonly property real thumbWidth: Math.round(Math.max(150, Math.min(260, 145 * winAspect)))
                            readonly property real thumbHeight: Math.round(Math.max(96, Math.min(175, thumbWidth / winAspect)))
                            readonly property bool minimized: DockService.isMinimized(modelData)
                            readonly property bool isFocused: DockService.cleanAddress(modelData) === DockService.activeAddress
                            readonly property string wsLabel: DockService.workspaceLabel(modelData)
                            readonly property bool hovered: cardHover.containsMouse || closeHover.containsMouse

                            onHoveredChanged: {
                                if (hovered)
                                    root.hoveredCardCount++;
                                else
                                    root.hoveredCardCount = Math.max(0, root.hoveredCardCount - 1);
                            }

                            Component.onDestruction: {
                                if (hovered)
                                    root.hoveredCardCount = Math.max(0, root.hoveredCardCount - 1);
                            }

                            implicitWidth: thumbWidth + Tokens.padding.small * 2
                            implicitHeight: cardCol.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.medium
                            color: hovered ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer
                            border.width: 1
                            border.color: isFocused || hovered ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

                            Behavior on border.color {
                                CAnim {}
                            }

                            MouseArea {
                                id: cardHover

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.windowActivated(card.modelData)
                            }

                            ColumnLayout {
                                id: cardCol

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.small

                                    IconImage {
                                        asynchronous: true
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitSize: 16
                                        source: root.targetItem?.icon ?? ""
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: card.modelData?.title || root.targetItem?.name || ""
                                        color: Colours.palette.m3onSurface
                                        font: Tokens.font.label.medium
                                        elide: Text.ElideRight
                                    }

                                    StyledRect {
                                        visible: card.wsLabel.length > 0
                                        implicitWidth: wsText.implicitWidth + Tokens.padding.small * 1.4
                                        implicitHeight: wsText.implicitHeight + Tokens.padding.extraSmall
                                        radius: Tokens.rounding.full
                                        color: card.isFocused ? Colours.palette.m3primaryContainer : card.minimized ? Colours.tPalette.m3surfaceContainerHighest : Colours.palette.m3secondaryContainer

                                        StyledText {
                                            id: wsText

                                            anchors.centerIn: parent
                                            text: card.wsLabel
                                            color: card.isFocused ? Colours.palette.m3onPrimaryContainer : card.minimized ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSecondaryContainer
                                            font: Tokens.font.label.small
                                        }
                                    }

                                    StyledRect {
                                        id: closeBtn

                                        implicitWidth: 20
                                        implicitHeight: 20
                                        radius: Tokens.rounding.full
                                        color: closeHover.containsMouse ? Colours.palette.m3errorContainer : "transparent"

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: "close"
                                            color: closeHover.containsMouse ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                                            fontStyle: Tokens.font.icon.small
                                        }

                                        MouseArea {
                                            id: closeHover

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.windowClosed(card.modelData)
                                        }
                                    }
                                }

                                ClippingRectangle {
                                    id: frame

                                    Layout.preferredWidth: card.thumbWidth
                                    Layout.preferredHeight: card.thumbHeight
                                    radius: Tokens.rounding.small
                                    color: Colours.tPalette.m3surfaceContainerHighest
                                    border.width: 1
                                    border.color: Qt.alpha(Colours.palette.m3outline, 0.35)

                                    ScreencopyView {
                                        id: screencopy

                                        anchors.fill: parent
                                        captureSource: root.open && !card.minimized ? (card.modelData?.wayland ?? null) : null
                                        live: root.open && !card.minimized && card.modelData !== null
                                        constraintSize: Qt.size(frame.width, frame.height)
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Tokens.spacing.extraSmall
                                        visible: !screencopy.hasContent

                                        IconImage {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            asynchronous: true
                                            implicitSize: 32
                                            opacity: card.minimized ? 0.65 : 0.9
                                            source: root.targetItem?.icon ?? ""
                                        }

                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: card.minimized ? Tr.tr("Minimized") : Tr.tr("Preview unavailable")
                                            color: Colours.palette.m3onSurfaceVariant
                                            font: Tokens.font.label.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
