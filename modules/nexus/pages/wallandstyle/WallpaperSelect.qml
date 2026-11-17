pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Models
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool isAnimatedMode: Wallpapers.wallpaperMode === "animated"
    readonly property string animatedRootDir: `${Paths.wallsdir}/Animated`
    readonly property bool flatAnimatedDir: {
        if (!isAnimatedMode)
            return false;
        const walls = Wallpapers.animatedList;
        return walls.length > 0 && walls.every(w => w.parentDir === animatedRootDir);
    }

    title: Tr.tr("Wallpapers")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        SegmentedBar {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Tokens.spacing.small
            currentIndex: root.isAnimatedMode ? 1 : 0
            model: [
                {
                    icon: "image",
                    text: Tr.tr("Static")
                },
                {
                    icon: "movie",
                    text: Tr.tr("Animated")
                }
            ]
            onActivated: idx => Wallpapers.setWallpaperMode(idx === 1 ? "animated" : "static")
        }

        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.medium
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "photo_library"
                text: Tr.tr("Browse")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: browseDialog.open()

                FileDialog {
                    id: browseDialog

                    title: root.isAnimatedMode ? Tr.tr("Select a video wallpaper") : Tr.tr("Select an image")
                    filterLabel: root.isAnimatedMode ? Tr.tr("Video files") : Tr.tr("Image files")
                    filters: root.isAnimatedMode ? Wallpapers.validVideoExtensions : Images.validImageExtensions
                    onAccepted: path => {
                        Wallpapers.setWallpaper(path);
                        root.nState.closeSubPage();
                    }
                }
            }

            IconTextButton {
                icon: "shuffle"
                text: Tr.tr("Random")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                type: IconTextButton.Tonal
                onClicked: {
                    Wallpapers.setRandom();
                    root.nState.closeSubPage();
                }
            }

            IconTextButton {
                visible: root.isAnimatedMode
                icon: "refresh"
                text: Wallpapers.extractingThumbs ? Tr.tr("Processing...") : Tr.tr("Refresh")
                disabled: Wallpapers.extractingThumbs
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                type: IconTextButton.Tonal
                onClicked: Wallpapers.refreshAnimatedThumbs(true)
            }
        }

        // Rotation
        SectionHeader {
            text: Tr.tr("Rotation")
        }

        ToggleRow {
            first: true
            text: Tr.tr("New random wallpaper at startup")
            subtext: Tr.tr("Pick a random wallpaper each time the shell starts")
            checked: GlobalConfig.background.randomWallpaperOnStart
            onToggled: GlobalConfig.background.randomWallpaperOnStart = checked
        }

        ToggleRow {
            text: Tr.tr("Cycle wallpapers")
            subtext: Tr.tr("Switch to another random wallpaper on a timer")
            checked: GlobalConfig.background.wallpaperCycle
            onToggled: GlobalConfig.background.wallpaperCycle = checked
        }

        StepperRow {
            last: true
            enabled: GlobalConfig.background.wallpaperCycle
            label: Tr.tr("Cycle interval")
            // TRANSLATORS: min is the minute unit, leave it untranslated
            subtext: Tr.tr("How often the wallpaper changes (min)")
            value: Math.round(GlobalConfig.background.wallpaperCycleInterval / 60000)
            from: 1
            to: 240
            stepSize: 5
            onMoved: v => GlobalConfig.background.wallpaperCycleInterval = Math.round(v * 60000)
        }

        WallItem {
            Layout.topMargin: Tokens.spacing.medium
            visible: !root.isAnimatedMode
            imgHeight: Math.round(width * 0.3)
            radius: Tokens.rounding.extraLarge
            source: Quickshell.shellPath("assets/wallpaper.webp")
            text: Tr.tr("Featured wallpaper")
            fillLabel: false
            onClicked: {
                Wallpapers.setWallpaper(Quickshell.shellPath("assets/wallpaper.webp"));
                root.nState.closeSubPage();
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.large
            text: root.isAnimatedMode ? Tr.tr("Animated wallpapers") : Tr.tr("Local wallpapers")
            font: Tokens.font.title.small
        }

        GridLayout {
            Layout.fillWidth: true
            visible: localWalls.count > 0

            columns: Config.nexus.wallpapersPerRow
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.large

            Repeater {
                id: localWalls

                model: {
                    const walls = root.isAnimatedMode ? Wallpapers.animatedList : Wallpapers.staticList;
                    if (root.flatAnimatedDir) {
                        const flat = [...walls].sort((a, b) => a.name.localeCompare(b.name));
                        while (flat.length < Config.nexus.wallpapersPerRow)
                            flat.push(null);
                        return flat;
                    }

                    const baseDir = Paths.wallsdir;
                    const categories = {};
                    const list = [];
                    for (const w of walls) {
                        if (w.parentDir !== baseDir) {
                            const category = Wallpapers.getCategoryFor(w);
                            if (category && (!(category in categories) || categories[category].name.localeCompare(w.name) > 0))
                                categories[category] = w;
                        } else {
                            list.push(w);
                        }
                    }
                    list.push(...Object.values(categories));
                    list.sort((a, b) => ((a.parentDir === baseDir) - (b.parentDir === baseDir)) || a.name.localeCompare(b.name));
                    if (list.length > 0) {
                        while (list.length < Config.nexus.wallpapersPerRow)
                            list.push(null);
                    }
                    return list;
                }

                WallItem {
                    required property FileSystemEntry modelData

                    // Empty placeholders for sizing
                    opacity: modelData ? 1 : 0
                    enabled: modelData

                    source: String(modelData?.path ?? "")
                    text: {
                        if (!modelData)
                            return "";

                        if (!root.flatAnimatedDir && modelData.parentDir !== Paths.wallsdir) {
                            const category = Wallpapers.getCategoryFor(modelData);
                            return category.slice(0, 1).toUpperCase() + category.slice(1);
                        }
                        return modelData.name;
                    }
                    onClicked: {
                        if (!root.flatAnimatedDir && modelData.parentDir !== Paths.wallsdir) {
                            root.nState.selectedWallpaperCategory = Wallpapers.getCategoryFor(modelData);
                            root.nState.openSubPage(2); // Category page
                        } else {
                            Wallpapers.setWallpaper(modelData.path);
                            root.nState.closeSubPage();
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true

            asynchronous: true
            active: localWalls.count === 0
            visible: active

            sourceComponent: StyledRect {
                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.extraLarge
                implicitHeight: noWallsLayout.implicitHeight + Tokens.padding.extraExtraLarge * 2

                ColumnLayout {
                    id: noWallsLayout

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.isAnimatedMode ? "movie" : "hide_image"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.isAnimatedMode ? Tr.tr("No animated wallpapers found") : Tr.tr("No local wallpapers found")
                        color: Colours.palette.m3outline
                        font: Tokens.font.title.small
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.isAnimatedMode
                        text: Tr.tr("Put video wallpapers (.mp4, .webm, .mkv) in %1").arg(Paths.shortenHome(`${Paths.wallsdir}/Animated`))
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }
                }
            }
        }
    }
}
