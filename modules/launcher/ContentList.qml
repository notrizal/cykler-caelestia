pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property var currentList: showWallpapers ? wallpaperList.item : appList.item // Can be either ListView or PathView, so can't type properly

    property string animState: showWallpapers ? "wallpapers" : "apps"

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: wallpaperList.implicitHeight > 0 ? wallpaperList.implicitHeight : root.Tokens.sizes.launcher.wallpaperHeight
                wallpaperList.active: true
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    Behavior on implicitWidth {
        enabled: root.screenState.launcher

        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState.launcher

        Anim {}
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: ColumnLayout {
            id: wallpaperContainer

            property alias count: listComp.count
            property alias currentItem: listComp.currentItem

            function incrementCurrentIndex(): void {
                listComp.incrementCurrentIndex();
            }

            function decrementCurrentIndex(): void {
                listComp.decrementCurrentIndex();
            }

            spacing: root.Tokens.spacing.small
            implicitWidth: Math.max(modeRow.implicitWidth, listComp.implicitWidth)

            RowLayout {
                id: modeRow

                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.padding.small
                spacing: Tokens.spacing.medium

                IconTextButton {
                    icon: "image"
                    text: Tr.tr("Static")
                    font: Tokens.font.label.medium
                    isRound: true
                    horizontalPadding: Tokens.padding.medium
                    verticalPadding: Tokens.padding.extraSmall
                    type: Wallpapers.wallpaperMode === "static" ? IconTextButton.Filled : IconTextButton.Tonal
                    onClicked: Wallpapers.setWallpaperMode("static")
                }

                IconTextButton {
                    icon: "movie"
                    text: Tr.tr("Animated")
                    font: Tokens.font.label.medium
                    isRound: true
                    horizontalPadding: Tokens.padding.medium
                    verticalPadding: Tokens.padding.extraSmall
                    type: Wallpapers.wallpaperMode === "animated" ? IconTextButton.Filled : IconTextButton.Tonal
                    onClicked: Wallpapers.setWallpaperMode("animated")
                }

                IconTextButton {
                    visible: Wallpapers.wallpaperMode === "animated"
                    icon: "refresh"
                    text: Wallpapers.extractingThumbs ? Tr.tr("Processing...") : Tr.tr("Refresh")
                    disabled: Wallpapers.extractingThumbs
                    font: Tokens.font.label.medium
                    isRound: true
                    horizontalPadding: Tokens.padding.medium
                    verticalPadding: Tokens.padding.extraSmall
                    type: IconTextButton.Tonal
                    onClicked: Wallpapers.refreshAnimatedThumbs(true)
                }
            }

            WallpaperList {
                id: listComp

                objectName: "launcherWallpaperList"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: root.Tokens.sizes.launcher.wallpaperHeight
                search: root.search
                screenState: root.screenState
                panels: root.panels
                content: root.content
            }
        }
    }

    Row {
        id: empty

        opacity: root.currentList?.count === 0 ? 1 : 0
        scale: root.currentList?.count === 0 ? 1 : 0.5

        spacing: Tokens.spacing.medium
        padding: Tokens.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.state === "wallpapers" ? Tokens.padding.large : 0

        MaterialIcon {
            text: root.state === "wallpapers" ? (Wallpapers.wallpaperMode === "animated" ? "movie" : "wallpaper_slideshow") : "manage_search"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.state === "wallpapers" ? (Wallpapers.wallpaperMode === "animated" ? Tr.tr("No animated wallpapers found") : Tr.tr("No wallpapers found")) : Tr.tr("No results")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: {
                    if (root.state !== "wallpapers")
                        return Tr.tr("Try searching for something else");
                    if (Wallpapers.list.length === 0) {
                        const targetDir = Wallpapers.wallpaperMode === "animated" ? `${Paths.wallsdir}/Animated` : Paths.wallsdir;
                        return Tr.tr("Try putting some wallpapers in %1").arg(Paths.shortenHome(targetDir));
                    }
                    return Tr.tr("Try searching for something else");
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }
}
