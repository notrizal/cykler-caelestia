pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Focus timer: progress ring on the left, synced controls on the right
RowLayout {
    id: root

    spacing: Tokens.spacing.large

    CircularProgress {
        implicitSize: 96
        strokeWidth: 7
        value: FocusTimer.progress
        fgColour: FocusTimer.isBreak ? Colours.palette.m3tertiary : !FocusTimer.active && !FocusTimer.connected && FocusTimer.remaining <= 0 ? Colours.palette.m3tertiary : Colours.palette.m3primary
        bgColour: Colours.palette.m3surfaceContainerHighest

        Behavior on clampedVal {
            Anim {}
        }

        StyledText {
            anchors.centerIn: parent
            text: FocusTimer.display
            color: Colours.palette.m3onSurface
            font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize).weight(Font.Bold).build()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: Number.POSITIVE_INFINITY
        spacing: Tokens.spacing.small

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: FocusTimer.phaseLabel
            color: FocusTimer.isBreak ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconButton {
                icon: FocusTimer.running ? "pause" : "play_arrow"
                type: IconButton.Filled
                onClicked: FocusTimer.toggle()
            }

            IconButton {
                visible: FocusTimer.active
                icon: "skip_next"
                type: IconButton.Tonal
                onClicked: FocusTimer.skip()
            }

            IconButton {
                icon: "restart_alt"
                type: IconButton.Tonal
                onClicked: FocusTimer.reset()
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            // When active (synced or local), offer +1 min extend; when idle locally, allow ±5 min
            IconButton {
                visible: !FocusTimer.connected && !FocusTimer.active
                icon: "remove"
                type: IconButton.Text
                onClicked: FocusTimer.adjust(-5)
            }

            StyledRect {
                implicitWidth: sourceRow.implicitWidth + Tokens.padding.small * 2
                implicitHeight: sourceRow.implicitHeight + 4
                radius: Tokens.rounding.full
                color: FocusTimer.connected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

                StateLayer {
                    color: FocusTimer.connected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    radius: parent.radius
                    onClicked: FocusTimer.openApp()
                }

                RowLayout {
                    id: sourceRow

                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        text: FocusTimer.connected ? "sync" : "open_in_new"
                        color: FocusTimer.connected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: FocusTimer.connected ? "Focus Timer" : `${Math.round(FocusTimer.durationSecs / 60)} min · Open App`
                        color: FocusTimer.connected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }

            IconButton {
                visible: !FocusTimer.connected && !FocusTimer.active
                icon: "add"
                type: IconButton.Text
                onClicked: FocusTimer.adjust(5)
            }

            IconButton {
                visible: FocusTimer.active
                icon: "more_time"
                type: IconButton.Text
                onClicked: FocusTimer.extendMins(1)
            }
        }
    }
}
