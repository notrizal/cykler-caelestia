pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Multimedia
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property string source
    property alias text: label.text
    property alias radius: imgWrapper.radius
    property alias imgHeight: imgWrapper.implicitHeight
    property bool fillLabel: true

    readonly property bool isVideo: Wallpapers.isVideo(source)
    readonly property string videoThumbSource: isVideo ? Wallpapers.getWallpaperThumb(source, Wallpapers.thumbBusterFor(source)) : ""
    readonly property bool imageReady: isVideo ? videoThumb.status === Image.Ready : img.ready

    signal clicked

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.small

        ClipRect {
            id: imgWrapper

            Layout.fillWidth: true
            implicitHeight: width
            radius: Tokens.rounding.largeIncreased
            color: Colours.tPalette.m3surfaceContainer

            Loader {
                anchors.centerIn: parent

                opacity: root.imageReady ? 0 : 1
                active: opacity > 0

                sourceComponent: StyledRect {
                    implicitWidth: loadingIndicator.implicitSize + Tokens.padding.large * 2
                    implicitHeight: loadingIndicator.implicitSize + Tokens.padding.large * 2

                    color: Colours.palette.m3primaryContainer
                    radius: Tokens.rounding.full

                    LoadingIndicator {
                        id: loadingIndicator

                        anchors.centerIn: parent
                        containsIcon: true
                        implicitSize: Math.min(imgWrapper.width, imgWrapper.height) * 0.3
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            Visual {
                id: img

                anchors.fill: parent
                source: root.isVideo ? "" : root.source
                playing: false
                visible: !root.isVideo
            }

            // Videos render a cached JPEG thumbnail here instead of spawning a QMediaPlayer per grid cell
            Image {
                id: videoThumb

                anchors.fill: parent
                visible: root.isVideo
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                retainWhileLoading: true
                source: root.videoThumbSource
                sourceSize: {
                    const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                    return Qt.size(Math.max(1, width * dpr), Math.max(1, height * dpr));
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
                implicitWidth: videoBadgeIcon.implicitWidth + Tokens.padding.small
                implicitHeight: videoBadgeIcon.implicitHeight + Tokens.padding.extraSmall
                radius: Tokens.rounding.small
                color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.85)

                MaterialIcon {
                    id: videoBadgeIcon

                    anchors.centerIn: parent
                    text: "movie"
                    color: Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.small
                }
            }
        }

        StyledText {
            id: label

            Layout.bottomMargin: Tokens.padding.small
            Layout.fillWidth: true
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    StateLayer {
        id: stateLayer

        anchors.bottomMargin: root.fillLabel ? 0 : layout.implicitHeight - imgWrapper.implicitHeight
        onClicked: root.clicked()
    }
}
