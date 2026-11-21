import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// What the bar has no room for: how much is left, when it ends, and the controls to pause or clear it
ColumnLayout {
    id: root

    readonly property bool useFocus: !CountdownTimer.active && FocusTimer.active
    readonly property string statusText: {
        if (useFocus)
            return FocusTimer.connected ? Tr.tr("Synced with Focus Timer") : Tr.tr("Local Pomodoro");
        if (CountdownTimer.finished)
            return Tr.tr("Timer finished");
        if (CountdownTimer.running)
            return Tr.tr("Ends at %1").arg(Qt.formatTime(new Date(CountdownTimer.endAt), Units.twelveHourClock ? "h:mm A" : "HH:mm"));
        return Tr.tr("Paused with %1 left").arg(CountdownTimer.display);
    }

    spacing: Tokens.spacing.small

    StyledText {
        text: root.useFocus ? FocusTimer.phaseLabel : (CountdownTimer.finished ? Tr.tr("Time's up") : Tr.tr("Timer"))
        color: root.useFocus ? (FocusTimer.isBreak ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant) : (CountdownTimer.finished ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant)
        font: Tokens.font.label.medium
    }

    StyledText {
        text: root.useFocus ? FocusTimer.display : CountdownTimer.display
        color: Colours.palette.m3onSurface
        font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize).weight(Font.Bold).build()
    }

    StyledProgressBar {
        Layout.fillWidth: true
        Layout.preferredWidth: 180
        Layout.topMargin: Tokens.spacing.extraSmall
        value: root.useFocus ? FocusTimer.progress : CountdownTimer.progress
        fgColour: {
            if (root.useFocus)
                return FocusTimer.isBreak ? Colours.palette.m3tertiary : FocusTimer.running ? Colours.palette.m3primary : Colours.palette.m3outline;
            return CountdownTimer.finished ? Colours.palette.m3tertiary : CountdownTimer.progress > 0 && !CountdownTimer.running ? Colours.palette.m3outline : Colours.palette.m3primary;
        }
    }

    StyledText {
        text: root.statusText
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    StyledText {
        visible: !root.useFocus
        text: Tr.tr("%1 in all").arg(CountdownTimer.durationDisplay)
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
    }

    RowLayout {
        Layout.topMargin: Tokens.spacing.small
        spacing: Tokens.spacing.small

        IconButton {
            visible: root.useFocus || !CountdownTimer.finished
            icon: (root.useFocus ? FocusTimer.running : CountdownTimer.running) ? "pause" : "play_arrow"
            type: IconButton.Tonal
            onClicked: root.useFocus ? FocusTimer.toggle() : CountdownTimer.toggle()
        }

        TextButton {
            visible: root.useFocus
            text: "+1m"
            type: TextButton.Text
            onClicked: FocusTimer.extendMins(1)
        }

        TextButton {
            visible: root.useFocus
            text: Tr.tr("Skip")
            type: TextButton.Text
            onClicked: FocusTimer.skip()
        }

        TextButton {
            text: root.useFocus ? Tr.tr("Stop") : (CountdownTimer.finished ? Tr.tr("Dismiss") : Tr.tr("Cancel"))
            type: TextButton.Text
            onClicked: root.useFocus ? FocusTimer.reset() : (CountdownTimer.finished ? CountdownTimer.dismiss() : CountdownTimer.reset())
        }
    }
}
