import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Models
import Caelestia.Multimedia
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property FileSystemEntry modelData
    required property ScreenState screenState

    readonly property bool isVideo: Wallpapers.isVideo(modelData.path)
    readonly property string videoThumbSource: isVideo ? Wallpapers.getWallpaperThumb(modelData.path, Wallpapers.thumbBusterFor(modelData.path)) : ""

    scale: 0.5
    opacity: 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    Component.onCompleted: {
        scale = Qt.binding(() => PathView.isCurrentItem ? 1 : PathView.onPath ? 0.8 : 0);
        opacity = Qt.binding(() => PathView.onPath ? 1 : 0);
    }

    implicitWidth: image.width + Tokens.padding.medium * 2
    implicitHeight: image.height + label.height + Tokens.spacing.extraSmall + Tokens.padding.large + Tokens.padding.medium

    StateLayer {
        id: stateLayer

        radius: Tokens.rounding.large
        onClicked: {
            Wallpapers.setWallpaper(root.modelData.path);
            root.screenState.launcher = false;
        }
    }

    Elevation {
        anchors.fill: image
        radius: image.radius
        opacity: root.PathView.isCurrentItem ? 1 : 0
        level: 4

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    ClipRect {
        id: image

        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.padding.large
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        implicitWidth: Tokens.sizes.launcher.wallpaperWidth
        implicitHeight: implicitWidth / 16 * 9

        MaterialIcon {
            anchors.centerIn: parent
            text: root.isVideo ? "movie" : "image"
            color: Colours.tPalette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.DemiBold).build()
        }

        Visual {
            anchors.fill: parent
            source: root.isVideo ? "" : root.modelData.path
            playing: false
            visible: !root.isVideo
        }

        // Video thumbnails load asynchronously as 720p JPEGs instead of spawning MediaPlayers in the carousel
        Image {
            anchors.fill: parent
            visible: root.isVideo
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            retainWhileLoading: true
            smooth: !root.PathView.view?.moving ?? true
            source: root.videoThumbSource
            sourceSize: {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                return Qt.size(Math.max(1, image.implicitWidth * dpr), Math.max(1, image.implicitHeight * dpr));
            }
            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        StyledRect {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.padding.small
            visible: root.isVideo
            implicitWidth: badgeIcon.implicitWidth + Tokens.padding.small
            implicitHeight: badgeIcon.implicitHeight + Tokens.padding.extraSmall
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.85)

            MaterialIcon {
                id: badgeIcon

                anchors.centerIn: parent
                text: "movie"
                color: Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.small
            }
        }
    }

    StyledText {
        id: label

        anchors.top: image.bottom
        anchors.topMargin: Tokens.spacing.extraSmall
        anchors.horizontalCenter: parent.horizontalCenter

        width: image.width - Tokens.padding.medium * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.QtRendering
        text: root.modelData.relativePath
        font: Tokens.font.label.medium
    }

    Behavior on scale {
        Anim {}
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
