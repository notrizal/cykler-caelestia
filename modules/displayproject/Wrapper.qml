pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// Border-integrated bottom-right display projection switcher (Super+P), styled to
// blend into ContentWindow's BlobGroup surface and auto-apply 2s after cycling stops.
Item {
    id: root

    required property ScreenState screenState

    readonly property bool shouldBeActive: screenState?.displayProject ?? false
    readonly property var modes: [
        {
            id: "pc",
            icon: "laptop_windows",
            title: Tr.tr("PC screen only"),
            subtext: Tr.tr("Use only the built-in display")
        },
        {
            id: "duplicate",
            icon: "content_copy",
            title: Tr.tr("Duplicate"),
            subtext: Tr.tr("Mirror the same image on all displays")
        },
        {
            id: "extend",
            icon: "view_column_2",
            title: Tr.tr("Extend"),
            subtext: Tr.tr("Span desktop across displays side by side")
        },
        {
            id: "second",
            icon: "desktop_windows",
            title: Tr.tr("Second screen only"),
            subtext: Tr.tr("Use only the external display")
        }
    ]

    property int selectedIndex: 0
    property real offsetScale: shouldBeActive ? 0 : 1

    function cycle(): void {
        if (!screenState)
            return;

        if (!screenState.displayProject) {
            const current = Monitors.currentProjectionMode();
            const idx = modes.findIndex(m => m.id === current);
            selectedIndex = idx >= 0 ? idx : 0;
            screenState.utilities = false;
            screenState.launcher = false;
            screenState.session = false;
            screenState.dashboard = false;
            screenState.displayProject = true;
            focus = true;
        } else {
            selectedIndex = (selectedIndex + 1) % modes.length;
        }
        autoApplyTimer.restart();
    }

    function applySelected(): void {
        autoApplyTimer.stop();
        if (screenState)
            screenState.displayProject = false;
        const mode = modes[selectedIndex];
        if (mode)
            Monitors.applyProjectionMode(mode.id);
    }

    function cancel(): void {
        autoApplyTimer.stop();
        if (screenState)
            screenState.displayProject = false;
    }

    onShouldBeActiveChanged: {
        if (!shouldBeActive)
            autoApplyTimer.stop();
        else
            focus = true;
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitWidth: Math.max(300, contentCol.implicitWidth + Tokens.padding.large * 2)
    implicitHeight: contentCol.implicitHeight + Tokens.padding.large * 2
    opacity: 1 - offsetScale
    focus: shouldBeActive

    Keys.onEscapePressed: cancel()
    Keys.onReturnPressed: applySelected()
    Keys.onEnterPressed: applySelected()
    Keys.onUpPressed: {
        selectedIndex = (selectedIndex - 1 + modes.length) % modes.length;
        autoApplyTimer.restart();
    }
    Keys.onDownPressed: {
        selectedIndex = (selectedIndex + 1) % modes.length;
        autoApplyTimer.restart();
    }

    Behavior on offsetScale {
        Anim {}
    }

    Timer {
        id: autoApplyTimer

        interval: 2000
        repeat: false
        onTriggered: root.applySelected()
    }

    Connections {
        function onDisplayProjectRequested(): void {
            root.cycle();
        }

        target: root.screenState
    }

    ColumnLayout {
        id: contentCol

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.extraSmall
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "cast"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Project")
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.small
            }

            StyledText {
                text: "Super+P"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }

        Item {
            id: listTrack

            Layout.fillWidth: true
            implicitWidth: modesCol.implicitWidth
            implicitHeight: modesCol.implicitHeight

            StyledRect {
                id: activeIndicator

                readonly property Item activeItem: modeRepeater.count > root.selectedIndex ? modeRepeater.itemAt(root.selectedIndex) : null

                visible: !!activeItem
                x: activeItem?.x ?? 0
                y: activeItem?.y ?? 0
                width: activeItem?.width ?? 0
                height: activeItem?.height ?? 0
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary

                Behavior on y {
                    enabled: root.shouldBeActive

                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }

                Behavior on height {
                    enabled: root.shouldBeActive

                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
            }

            ColumnLayout {
                id: modesCol

                anchors.fill: parent
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    id: modeRepeater

                    model: root.modes

                    delegate: Item {
                        id: modeRow

                        required property var modelData
                        required property int index

                        readonly property bool selected: index === root.selectedIndex

                        Layout.fillWidth: true
                        implicitWidth: rowLayout.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: rowLayout.implicitHeight + Tokens.padding.small * 2

                        StateLayer {
                            radius: Tokens.rounding.full
                            color: modeRow.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            onClicked: {
                                root.selectedIndex = modeRow.index;
                                root.applySelected();
                            }
                        }

                        RowLayout {
                            id: rowLayout

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            anchors.topMargin: Tokens.padding.small
                            anchors.bottomMargin: Tokens.padding.small
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                Layout.alignment: Qt.AlignVCenter
                                text: modeRow.modelData.icon
                                color: modeRow.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.medium

                                Behavior on color {
                                    CAnim {}
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modeRow.modelData.title
                                    color: modeRow.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                    font: Tokens.font.body.small
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        CAnim {}
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modeRow.modelData.subtext
                                    color: modeRow.selected ? Qt.alpha(Colours.palette.m3onPrimary, 0.85) : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        CAnim {}
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
