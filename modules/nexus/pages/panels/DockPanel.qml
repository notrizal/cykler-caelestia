pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> visibilityItems: [
        MenuItem {
            text: Tr.tr("Always visible")
            icon: "visibility"
            value: DockVisibility.AlwaysShow
        },
        MenuItem {
            text: Tr.tr("Floating overlay")
            icon: "layers"
            value: DockVisibility.Floating
        },
        MenuItem {
            text: Tr.tr("Auto-hide")
            icon: "vertical_align_bottom"
            value: DockVisibility.AutoHide
        },
        MenuItem {
            text: Tr.tr("Dodge windows")
            icon: "auto_awesome_motion"
            value: DockVisibility.DodgeWindows
        }
    ]

    readonly property list<MenuItem> hoverEffectItems: [
        MenuItem {
            text: Tr.tr("Magnification")
            icon: "zoom_in"
            value: DockHoverEffect.Magnification
        },
        MenuItem {
            text: Tr.tr("Material highlight")
            icon: "highlight"
            value: DockHoverEffect.Highlight
        }
    ]

    readonly property var filteredApps: {
        const q = appSearch.text.trim().toLowerCase();
        const pinned = GlobalConfig.dock.pinnedApps;
        const normPinned = pinned.map(id => DockService.normalizeId(id));
        const apps = [...DesktopEntries.applications.values].filter(a => {
            if (!q)
                return true;
            return a.name.toLowerCase().includes(q)
                || a.id.toLowerCase().includes(q)
                || String(a.comment || "").toLowerCase().includes(q);
        });

        apps.sort((a, b) => {
            const idxA = normPinned.indexOf(DockService.normalizeId(a.id));
            const idxB = normPinned.indexOf(DockService.normalizeId(b.id));
            const pinA = idxA >= 0;
            const pinB = idxB >= 0;
            if (pinA !== pinB)
                return pinA ? -1 : 1;
            if (pinA && pinB)
                return idxA - idxB;
            return a.name.localeCompare(b.name);
        });
        return apps;
    }

    function movePinned(appId: string, delta: int): void {
        const list = [...GlobalConfig.dock.pinnedApps];
        const norm = DockService.normalizeId(appId);
        const idx = list.findIndex(id => DockService.normalizeId(id) === norm);
        const target = idx + delta;
        if (idx < 0 || target < 0 || target >= list.length)
            return;

        const tmp = list[idx];
        list[idx] = list[target];
        list[target] = tmp;
        GlobalConfig.dock.pinnedApps = list;
    }

    title: Tr.tr("Dock")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            // SEARCH: dock bottom panel taskbar apps enable
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("A bottom dock for pinned apps and running windows with live hover previews")
            checked: Config.dock.enabled
            onToggled: GlobalConfig.dock.enabled = checked
        }

        SelectRow {
            // SEARCH: dock visibility autohide floating always show dodge windows
            label: Tr.tr("Visibility")
            subtext: Tr.tr("Choose whether the dock reserves space, floats, auto-hides, or dodges windows")
            menuItems: root.visibilityItems
            active: root.visibilityItems.find(i => i.value === Config.dock.visibility) ?? root.visibilityItems[1]
            onSelected: item => GlobalConfig.dock.visibility = item.value
        }

        SelectRow {
            // SEARCH: dock hover effect magnification highlight zoom scale
            label: Tr.tr("Hover effect")
            subtext: Tr.tr("Visual style when moving the pointer over dock icons")
            menuItems: root.hoverEffectItems
            active: root.hoverEffectItems.find(i => i.value === Config.dock.hoverEffect) ?? root.hoverEffectItems[0]
            onSelected: item => GlobalConfig.dock.hoverEffect = item.value
        }

        ToggleRow {
            last: true
            // SEARCH: dock per monitor windows workspace filter
            text: Tr.tr("Only show windows from this monitor")
            subtext: Tr.tr("When off, running apps from every monitor and workspace appear on the dock")
            checked: Config.dock.perMonitorWindows
            onToggled: GlobalConfig.dock.perMonitorWindows = checked
        }

        // Appearance & timing
        SectionHeader {
            text: Tr.tr("Sizing & timing")
        }

        StepperRow {
            first: true
            // SEARCH: dock icon size px
            label: Tr.tr("Icon size")
            subtext: Tr.tr("Size of each application icon on the dock, in pixels")
            value: Config.dock.iconSize
            from: 28
            to: 72
            stepSize: 2
            onMoved: v => GlobalConfig.dock.iconSize = v
        }

        StepperRow {
            // SEARCH: dock preview hover delay ms
            label: Tr.tr("Preview delay")
            subtext: Tr.tr("Milliseconds before the live window preview opens on hover")
            value: Config.dock.previewDelay
            from: 40
            to: 600
            stepSize: 20
            onMoved: v => GlobalConfig.dock.previewDelay = v
        }

        StepperRow {
            last: true
            // SEARCH: dock autohide delay ms
            label: Tr.tr("Auto-hide delay")
            subtext: Tr.tr("Milliseconds before an auto-hidden or occluded dock slides back down")
            value: Config.dock.hideDelay
            from: 100
            to: 1500
            stepSize: 50
            onMoved: v => GlobalConfig.dock.hideDelay = v
        }

        // Monitors
        SectionHeader {
            text: Tr.tr("Monitors")
        }

        Repeater {
            id: monitorRepeater

            model: Screens.screens

            delegate: ToggleRow {
                required property ShellScreen modelData
                required property int index

                first: index === 0
                last: index === monitorRepeater.count - 1
                text: modelData.name
                subtext: Tr.tr("%1×%2").arg(modelData.width).arg(modelData.height)
                checked: !Strings.testRegexList(GlobalConfig.dock.excludedScreens, modelData.name)
                onToggled: {
                    const current = [...GlobalConfig.dock.excludedScreens];
                    if (checked)
                        GlobalConfig.dock.excludedScreens = current.filter(s => s !== modelData.name);
                    else if (!current.includes(modelData.name))
                        GlobalConfig.dock.excludedScreens = [...current, modelData.name];
                }
            }
        }

        // Pinned applications
        SectionHeader {
            text: Tr.tr("Pinned applications")
        }

        SearchBar {
            id: appSearch

            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.small
            placeholderText: Tr.tr("Search apps to pin...")
        }

        Repeater {
            id: appsRepeater

            model: ScriptModel {
                values: root.filteredApps
                objectProp: "id"
            }

            delegate: ConnectedRect {
                id: appRow

                required property DesktopEntry modelData
                required property int index

                readonly property bool pinned: DockService.isPinned(modelData.id)

                Layout.fillWidth: true
                first: index === 0
                last: index === appsRepeater.count - 1
                implicitHeight: rowContent.implicitHeight + rowContent.anchors.margins * 2

                StateLayer {
                    onClicked: DockService.togglePin(appRow.modelData.id)
                }

                RowLayout {
                    id: rowContent

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    IconImage {
                        asynchronous: true
                        implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.6)
                        source: DockService.iconSource(appRow.modelData, appRow.modelData.id)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: appRow.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: (appRow.modelData.comment || appRow.modelData.genericName) ?? ""
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        visible: appRow.pinned && GlobalConfig.dock.pinnedApps.length > 1
                        icon: "keyboard_arrow_up"
                        type: IconButton.Text
                        onClicked: root.movePinned(appRow.modelData.id, -1)
                    }

                    IconButton {
                        visible: appRow.pinned && GlobalConfig.dock.pinnedApps.length > 1
                        icon: "keyboard_arrow_down"
                        type: IconButton.Text
                        onClicked: root.movePinned(appRow.modelData.id, 1)
                    }

                    StyledSwitch {
                        cLayer: 2
                        checked: appRow.pinned
                        onToggled: {
                            DockService.togglePin(appRow.modelData.id);
                            checked = Qt.binding(() => appRow.pinned);
                        }
                    }
                }
            }
        }
    }
}
