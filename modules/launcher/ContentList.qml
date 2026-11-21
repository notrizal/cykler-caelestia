pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property string effectiveSearchText: search.text || screenState.launcherSearchRequest
    readonly property bool showWallpapers: effectiveSearchText.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property bool isClipboard: effectiveSearchText === `${GlobalConfig.launcher.actionPrefix}clip` || effectiveSearchText.startsWith(`${GlobalConfig.launcher.actionPrefix}clip `)
    readonly property bool hasBottomTabs: isClipboard
    readonly property var activeTabsModel: Clipboard.categories
    readonly property int activeTabIndex: Clipboard.activeCategoryIndex
    readonly property real clipTabsHeight: hasBottomTabs ? (clipTabsBar.implicitHeight + Tokens.spacing.small) : 0
    readonly property var currentList: showWallpapers ? wallpaperList.item : appList.item // Can be either ListView or PathView, so can't type properly

    property string animState: showWallpapers ? "wallpapers" : "apps"
    property int lastClipTabIndex: Clipboard.activeCategoryIndex
    property real clipSlideFrom: 0

    function triggerTabSlide(prev: int, next: int, count: int): void {
        if (!root.screenState.launcher || next === prev || count <= 0)
            return;

        let dir = next > prev ? 1 : -1;
        if (prev === count - 1 && next === 0)
            dir = 1;
        else if (prev === 0 && next === count - 1)
            dir = -1;

        root.clipSlideFrom = dir * 14;
        clipSlideAnim.restart();
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: animState

    onHasBottomTabsChanged: {
        if (!hasBottomTabs) {
            clipSlideAnim.stop();
            clipListSlide.x = 0;
            appList.opacity = 1;
        }
    }

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, (appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight) + root.clipTabsHeight)
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
        clip: true

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: root.hasBottomTabs ? clipTabsBar.top : parent.bottom
        anchors.bottomMargin: root.hasBottomTabs ? Tokens.spacing.small : 0

        transform: Translate {
            id: clipListSlide
        }

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
        }
    }

    RowLayout {
        id: clipTabsBar

        visible: root.hasBottomTabs
        z: 2
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.small

        StyledRect {
            id: clipTabsTrack

            readonly property Item activeTab: clipTabRepeater.count > 0 ? clipTabRepeater.itemAt(root.activeTabIndex) : null
            readonly property bool layoutSettled: root.hasBottomTabs && root.screenState.launcher && (activeTab?.width ?? 0) > 0
            property bool animReady: false

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.max(36, clearClipBtn.implicitHeight)
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainerHigh

            onLayoutSettledChanged: {
                if (layoutSettled) {
                    Qt.callLater(() => {
                        if (clipTabsTrack.layoutSettled)
                            clipTabsTrack.animReady = true;
                    });
                } else {
                    animReady = false;
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y !== 0)
                        Clipboard.cycleCategory(event.angleDelta.y < 0 ? 1 : -1);
                }
            }

            StyledRect {
                id: clipHighlight

                visible: clipTabsTrack.activeTab !== null && width > 0
                x: clipTabsTrack.activeTab ? clipTabsRow.x + clipTabsTrack.activeTab.x : clipTabsRow.x
                y: clipTabsRow.y
                width: clipTabsTrack.activeTab?.width ?? 0
                height: clipTabsRow.height
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary

                Behavior on x {
                    enabled: clipTabsTrack.animReady

                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on width {
                    enabled: clipTabsTrack.animReady

                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }

            RowLayout {
                id: clipTabsRow

                anchors.fill: parent
                anchors.margins: 3
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    id: clipTabRepeater

                    model: root.activeTabsModel

                    Item {
                        id: clipTab

                        required property var modelData
                        required property int index

                        readonly property bool isActive: root.activeTabIndex === index
                        readonly property real cover: {
                            if (width <= 0)
                                return isActive ? 1 : 0;
                            const left = clipTabsRow.x + x;
                            const right = left + width;
                            const overlap = Math.max(0, Math.min(clipHighlight.x + clipHighlight.width, right) - Math.max(clipHighlight.x, left));
                            return Math.min(1, overlap / width);
                        }
                        readonly property color fgColor: Qt.tint(Colours.palette.m3onSurfaceVariant, Qt.alpha(Colours.palette.m3onPrimary, cover))

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: tabContent.implicitWidth + Tokens.padding.medium * 2
                        clip: true

                        StateLayer {
                            color: clipTab.isActive ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            radius: Tokens.rounding.full
                            onClicked: Clipboard.setCategoryIndex(clipTab.index)
                        }

                        RowLayout {
                            id: tabContent

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - Tokens.padding.small * 2)
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                Layout.alignment: Qt.AlignVCenter
                                text: clipTab.modelData.icon ?? ""
                                color: clipTab.fgColor
                                fontStyle: Tokens.font.icon.small
                                fill: clipTab.cover
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                text: clipTab.modelData.text ?? ""
                                color: clipTab.fgColor
                                font: Tokens.font.label.medium
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        IconButton {
            id: clearClipBtn

            Layout.alignment: Qt.AlignVCenter
            visible: Clipboard.historyItems.length > 0
            type: IconButton.Tonal
            icon: "delete_sweep"
            isRound: true
            onClicked: Clipboard.clearHistory()
        }
    }

    ParallelAnimation {
        id: clipSlideAnim

        Anim {
            target: clipListSlide
            property: "x"
            from: root.clipSlideFrom
            to: 0
            type: Anim.DefaultEffects
        }

        Anim {
            target: appList
            property: "opacity"
            from: 0.72
            to: 1
            type: Anim.FastEffects
        }
    }

    Connections {
        function onActiveCategoryIndexChanged(): void {
            const next = Clipboard.activeCategoryIndex;
            const prev = root.lastClipTabIndex;
            root.lastClipTabIndex = next;

            if (root.isClipboard)
                root.triggerTabSlide(prev, next, Clipboard.categories.length);
        }

        target: Clipboard
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
        anchors.verticalCenterOffset: root.state === "wallpapers" ? Tokens.padding.large : (root.isClipboard ? -root.clipTabsHeight / 2 : 0)

        transform: Translate {
            x: clipListSlide.x
        }

        MaterialIcon {
            text: root.state === "wallpapers" ? (Wallpapers.wallpaperMode === "animated" ? "movie" : "wallpaper_slideshow") : root.isClipboard ? "content_paste_off" : "manage_search"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.state === "wallpapers" ? (Wallpapers.wallpaperMode === "animated" ? Tr.tr("No animated wallpapers found") : Tr.tr("No wallpapers found")) : root.isClipboard ? Tr.tr("No clipboard items") : Tr.tr("No results")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: {
                    if (root.isClipboard)
                        return Tr.tr("Press Tab to switch category or copy something new");
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
