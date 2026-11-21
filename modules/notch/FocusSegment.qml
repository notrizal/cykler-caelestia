pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// NOTE(fork): Focus / Pomodoro bubble beside the Notch pill, styled to match TimerSegment:
// a circular countdown ring in the bubble's resting state that opens out on hover with phase
// info and quick actions (+1m, Pause/Resume, Skip, Hide).
Item {
    id: root

    property real expandProg
    property bool mirrored

    readonly property real detailWidth: detail.implicitWidth
    readonly property color accent: FocusTimer.isBreak ? Colours.palette.m3tertiary : FocusTimer.running ? Colours.palette.m3primary : Colours.palette.m3outline
    readonly property real textProg: Math.max(0, Math.min(1, (root.expandProg - 0.4) / 0.6))

    signal dismissed
    signal activated

    Item {
        id: circle

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: root.mirrored ? undefined : parent.left
        anchors.right: root.mirrored ? parent.right : undefined

        implicitWidth: height

        CircularProgress {
            id: ring

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            strokeWidth: Math.max(3, Math.round(width / 12))
            value: FocusTimer.progress
            fgColour: root.accent
            bgColour: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

            Behavior on clampedVal {
                Anim {}
            }
        }

        StyledText {
            anchors.centerIn: parent

            width: ring.width - ring.strokeWidth * 3
            horizontalAlignment: Text.AlignHCenter
            text: FocusTimer.display
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.medium
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
        }

        StateLayer {
            radius: Tokens.rounding.full
            color: root.accent

            onClicked: root.activated()
        }
    }

    Item {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: root.mirrored ? parent.left : circle.right
        anchors.right: root.mirrored ? circle.left : parent.right

        visible: root.expandProg > 0.001
        clip: true

        RowLayout {
            id: detail

            LayoutMirroring.enabled: root.mirrored
            LayoutMirroring.childrenInherit: true

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: root.mirrored ? undefined : parent.left
            anchors.right: root.mirrored ? parent.right : undefined
            anchors.leftMargin: root.mirrored ? 0 : Tokens.spacing.small
            anchors.rightMargin: root.mirrored ? Tokens.spacing.small : 0

            opacity: root.textProg
            spacing: Tokens.spacing.extraSmall

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    text: FocusTimer.phaseLabel
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.large
                }

                StyledText {
                    text: FocusTimer.connected ? Tr.tr("Focus Timer synced") : Tr.tr("Local Pomodoro")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }

            IconButton {
                Layout.alignment: Qt.AlignVCenter
                icon: FocusTimer.running ? "pause" : "play_arrow"
                type: IconButton.Text
                padding: Tokens.padding.extraSmall / 2
                font: Tokens.font.icon.small
                onClicked: FocusTimer.toggle()
            }

            IconButton {
                Layout.alignment: Qt.AlignVCenter
                icon: "more_time"
                type: IconButton.Text
                padding: Tokens.padding.extraSmall / 2
                font: Tokens.font.icon.small
                onClicked: FocusTimer.extendMins(1)
            }

            IconButton {
                Layout.alignment: Qt.AlignVCenter
                icon: "skip_next"
                type: IconButton.Text
                padding: Tokens.padding.extraSmall / 2
                font: Tokens.font.icon.small
                onClicked: FocusTimer.skip()
            }

            IconButton {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Tokens.spacing.extraSmall
                icon: "close"
                type: IconButton.Text
                padding: Tokens.padding.extraSmall / 2
                font: Tokens.font.icon.small
                onClicked: root.dismissed()
            }
        }
    }
}
