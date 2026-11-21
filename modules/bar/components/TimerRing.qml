pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// The running timer as a ring, in a section of its own under the bar's clock. The entry it fills hides itself while
// no timer is set (see modules/bar/Bar.qml), so this only has to draw one.
StyledRect {
    id: root

    readonly property int size: Tokens.sizes.bar.innerWidth
    readonly property bool useFocus: !CountdownTimer.active && FocusTimer.active

    implicitWidth: root.size
    implicitHeight: root.size

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    // Flashes once it has rung, so the count finishing is noticed even with the sound off. Held steady when
    // animations are switched off in Power & battery
    SequentialAnimation {
        running: CountdownTimer.finished && PowerSaving.animations
        loops: Animation.Infinite

        onRunningChanged: {
            if (!running)
                root.opacity = 1;
        }

        NumberAnimation {
            target: root
            property: "opacity"
            to: 0.25
            duration: 550
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: 550
            easing.type: Easing.InOutQuad
        }
    }

    CircularProgress {
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall / 2

        strokeWidth: 3
        value: root.useFocus ? FocusTimer.progress : CountdownTimer.progress
        // A paused count stays visible but steps back to the outline colour, and one that has rung turns tertiary
        fgColour: {
            if (root.useFocus)
                return FocusTimer.isBreak ? Colours.palette.m3tertiary : FocusTimer.running ? Colours.palette.m3primary : Colours.palette.m3outline;
            return CountdownTimer.finished ? Colours.palette.m3tertiary : CountdownTimer.running ? Colours.palette.m3primary : Colours.palette.m3outline;
        }
        bgColour: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

        Behavior on clampedVal {
            Anim {}
        }
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: root.useFocus ? (FocusTimer.isBreak ? "coffee" : "center_focus_strong") : (CountdownTimer.finished ? "alarm" : "timer")
        color: {
            if (root.useFocus)
                return FocusTimer.isBreak ? Colours.palette.m3tertiary : FocusTimer.running ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant;
            return CountdownTimer.finished ? Colours.palette.m3tertiary : CountdownTimer.running ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant;
        }
        fontStyle: Tokens.font.icon.small
    }
}
