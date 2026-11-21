pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Interactive Dynamic Island activity shown:
// 1. Right before a Pomodoro ends (or when confirmation is pending): +1m, +5m, Take Break, or Dismiss.
// 2. Right after a Break finishes (FocusTimer.waitingForInput): "Get ready" notification while waiting
//    for the user's mouse movement or keypress to start the next Pomodoro.
RowLayout {
    id: root

    spacing: Tokens.spacing.medium

    Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Tokens.padding.extraLarge
        implicitHeight: Tokens.padding.extraLarge

        CircularProgress {
            anchors.fill: parent
            strokeWidth: 3
            value: FocusTimer.waitingForInput ? 1 : FocusTimer.progress
            fgColour: FocusTimer.waitingForInput ? Colours.palette.m3tertiary : Colours.palette.m3primary
            bgColour: Qt.alpha(Colours.palette.m3outlineVariant, 0.45)

            Behavior on clampedVal {
                Anim {}
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: FocusTimer.waitingForInput ? "bolt" : "timer"
            color: FocusTimer.waitingForInput ? Colours.palette.m3tertiary : Colours.palette.m3primary
            fontStyle: Tokens.font.icon.small
            fill: 1
        }
    }

    ColumnLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: 0

        StyledText {
            text: FocusTimer.waitingForInput ? Tr.tr("Get ready") : (FocusTimer.confirmPending ? Tr.tr("Pomodoro finished") : Tr.tr("Pomodoro ending · %1").arg(FocusTimer.display))
            color: Colours.palette.m3onSurface
            font: Tokens.font.title.small
        }

        StyledText {
            visible: !FocusTimer.waitingForInput
            text: Tr.tr("Extend time or start break now?")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    RowLayout {
        visible: !FocusTimer.waitingForInput
        Layout.alignment: Qt.AlignVCenter
        spacing: Tokens.spacing.extraSmall

        ActionChip {
            text: "+1m"
            primary: false
            onClicked: FocusTimer.extendMins(1)
        }

        ActionChip {
            text: "+5m"
            primary: false
            onClicked: FocusTimer.extendMins(5)
        }

        ActionChip {
            text: Tr.tr("Break")
            primary: true
            onClicked: FocusTimer.takeBreakNow()
        }

        IconButton {
            Layout.alignment: Qt.AlignVCenter
            icon: "close"
            type: IconButton.Text
            padding: Tokens.padding.extraSmall / 2
            font: Tokens.font.icon.small
            onClicked: FocusTimer.dismissPrompt()
        }
    }

    component ActionChip: StyledRect {
        id: chip

        required property string text
        required property bool primary

        signal clicked

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: chipLabel.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: 28
        radius: Tokens.rounding.full
        color: primary ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

        StateLayer {
            color: chip.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
            radius: parent.radius
            onClicked: chip.clicked()
        }

        StyledText {
            id: chipLabel

            anchors.centerIn: parent
            text: chip.text
            color: chip.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
            font: Tokens.font.label.medium
        }
    }
}
