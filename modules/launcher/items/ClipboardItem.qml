pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property var modelData
    required property var list

    readonly property bool isImage: modelData?.isImage ?? false
    readonly property bool isPinned: modelData?.isPinned ?? false
    readonly property bool isClearAction: modelData?.isClearAction ?? false
    readonly property bool isMonospace: modelData?.isMonospace ?? false
    readonly property bool showSectionBreak: modelData?.showSectionBreak ?? false
    readonly property bool isCurrent: list?.currentItem === root
    readonly property string clipId: modelData?.clipId ?? ""
    readonly property string swatchColour: modelData?.swatch ?? ""
    readonly property string badgeLabel: modelData?.badgeLabel ?? ""
    readonly property string badgeTone: modelData?.badgeTone ?? "neutral"
    readonly property string imageSource: {
        void Clipboard.imageRevision;
        return isImage && clipId ? (Clipboard.imagePaths[clipId] ?? "") : "";
    }

    readonly property color toneBg: {
        if (isClearAction)
            return Qt.alpha(Colours.palette.m3errorContainer, 0.75);
        if (badgeTone === "primary")
            return Qt.alpha(Colours.palette.m3primaryContainer, 0.75);
        if (badgeTone === "tertiary")
            return Qt.alpha(Colours.palette.m3tertiaryContainer, 0.75);
        if (badgeTone === "secondary")
            return Qt.alpha(Colours.palette.m3secondaryContainer, 0.75);
        return Colours.tPalette.m3surfaceContainerHigh;
    }

    readonly property color toneFg: {
        if (isClearAction)
            return Colours.palette.m3onErrorContainer;
        if (badgeTone === "primary")
            return Colours.palette.m3onPrimaryContainer;
        if (badgeTone === "tertiary")
            return Colours.palette.m3onTertiaryContainer;
        if (badgeTone === "secondary")
            return Colours.palette.m3onSecondaryContainer;
        return Colours.palette.m3onSurfaceVariant;
    }

    function requestThumb(): void {
        if (root.isImage && root.clipId)
            Clipboard.ensureImagePreview(root.clipId, root.modelData?.imageExt ?? "png");
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    Component.onCompleted: requestThumb()
    onModelDataChanged: requestThumb()

    HoverHandler {
        id: rowHover
    }

    // Subtle hairline separating pinned snippets from recent clipboard history
    StyledRect {
        visible: root.showSectionBreak
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        height: 1
        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.55)
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.modelData?.onClicked(root.list)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.topMargin: Tokens.padding.small
        anchors.bottomMargin: Tokens.padding.small
        spacing: Tokens.spacing.medium

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.isImage ? 48 : 38
            implicitHeight: 38

            ClippingRectangle {
                anchors.fill: parent
                visible: root.isImage
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceContainerHigh
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

                Image {
                    id: thumb

                    anchors.fill: parent
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    source: root.imageSource
                    sourceSize.width: 96
                    sourceSize.height: 76
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: thumb.status !== Image.Ready
                    text: "image"
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            StyledRect {
                anchors.fill: parent
                visible: !root.isImage && root.swatchColour.length > 0
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceContainerHigh

                StyledRect {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    radius: Tokens.rounding.full
                    color: root.swatchColour || "transparent"
                    border.width: 1.5
                    border.color: Qt.alpha(Colours.palette.m3outline, 0.7)
                }
            }

            StyledRect {
                anchors.fill: parent
                visible: !root.isImage && root.swatchColour.length === 0
                radius: Tokens.rounding.small
                color: root.toneBg

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.modelData?.icon ?? "content_paste"
                    color: root.toneFg
                    fontStyle: Tokens.font.icon.medium
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.modelData?.name ?? ""
                font: root.isMonospace ? Tokens.font.mono.small : Tokens.font.body.medium
                color: root.isClearAction ? Colours.palette.m3error : Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledRect {
                    visible: root.badgeLabel.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: badgeText.implicitWidth + Tokens.padding.small * 1.4
                    implicitHeight: badgeText.implicitHeight + 2
                    radius: Tokens.rounding.full
                    color: root.toneBg

                    StyledText {
                        id: badgeText

                        anchors.centerIn: parent
                        text: root.badgeLabel
                        color: root.toneFg
                        font: Tokens.font.label.small
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.modelData?.desc ?? ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.extraSmall

            IconButton {
                visible: !root.isImage && !root.isClearAction && (root.isPinned || rowHover.hovered || root.isCurrent)
                type: IconButton.Text
                icon: "keep"
                label.fill: root.isPinned ? 1 : 0
                inactiveOnColour: root.isPinned ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                onClicked: Clipboard.togglePin(root.modelData)
            }

            IconButton {
                visible: !root.isClearAction && (rowHover.hovered || root.isCurrent)
                type: IconButton.Text
                icon: "close"
                inactiveOnColour: Colours.palette.m3onSurfaceVariant
                onClicked: Clipboard.deleteItem(root.modelData)
            }
        }
    }
}
