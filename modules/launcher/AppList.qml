pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.items
import qs.modules.launcher.services

StyledListView {
    id: root

    required property SearchBar search
    required property ScreenState screenState

    property string displayText: search.text || screenState.launcherSearchRequest

    readonly property string effectiveSearchText: search.text || screenState.launcherSearchRequest
    readonly property string requestedState: stateForText(effectiveSearchText)
    readonly property string displayState: stateForText(displayText)

    function syncDisplayText(): void {
        if (screenState.launcher && requestedState === displayState)
            displayText = effectiveSearchText;
    }

    function stateForText(text: string): string {
        const prefix = GlobalConfig.launcher.actionPrefix;
        if (text.startsWith(prefix)) {
            if (text.startsWith(`${prefix}calc `))
                return "calc";

            if (GlobalConfig.launcher.enableAiSearch && (text === `${prefix}ai` || text.startsWith(`${prefix}ai `)))
                return "ai";

            if (text === `${prefix}gpu` || text.startsWith(`${prefix}gpu `))
                return "gpu";

            if (text === `${prefix}ssh` || text.startsWith(`${prefix}ssh `))
                return "ssh";

            if (text === `${prefix}b` || text.startsWith(`${prefix}b `))
                return "browser";

            if (text === `${prefix}clip` || text.startsWith(`${prefix}clip `))
                return "clipboard";

            if (text === `${prefix}convert` || text.startsWith(`${prefix}convert `))
                return "convert";

            return "actions";
        }

        return "apps";
    }

    function resultsForText(text: string): var {
        switch (stateForText(text)) {
        case "actions":
            return Actions.query(text);
        case "calc":
            return [0];
        case "ai":
            return [0];
        case "gpu":
            return Supergfxctl.modeData;
        case "ssh":
            return SSH.search(text);
        case "browser":
            return [0];
        case "clipboard":
            return Clipboard.search(text);
        case "convert":
            return [0];
        default:
            return Apps.search(text);
        }
    }

    model: ScriptModel {
        values: {
            SSH.hostRevision;
            Supergfxctl.modeRevision;
            Supergfxctl.modeData;
            Clipboard.revision;
            return root.resultsForText(root.displayText);
        }
        onValuesChanged: root.currentIndex = 0
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    clip: true
    // The AI answer is one tall wrapping row, so its real content height is
    // used there; every other delegate is a fixed-height row, still capped by
    // maxShown. ContentList clamps the whole thing to maxHeight either way.
    implicitHeight: (state === "ai" || state === "convert") ? contentHeight : (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        visible: root.state !== "convert"
        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {}
        }
    }

    state: screenState.launcher ? requestedState : displayState

    onStateChanged: {
        if (state === "gpu")
            Supergfxctl.reload();
        else if (state === "ssh")
            SSH.reload();
        else if (state === "clipboard")
            Clipboard.reload();
    }

    Component.onCompleted: {
        displayText = effectiveSearchText;
        if (requestedState === "clipboard")
            Clipboard.reload();
    }

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                root.delegate: calcItem
            }
        },
        State {
            name: "ai"

            PropertyChanges {
                root.delegate: aiItem
            }
        },
        State {
            name: "gpu"

            PropertyChanges {
                root.delegate: actionItem
            }
        },
        State {
            name: "ssh"

            PropertyChanges {
                root.delegate: sshItem
            }
        },
        State {
            name: "browser"

            PropertyChanges {
                root.delegate: browserItem
            }
        },
        State {
            name: "clipboard"

            PropertyChanges {
                root.delegate: clipboardItem
            }
        },
        State {
            name: "convert"

            PropertyChanges {
                root.delegate: convertItem
            }
        }
    ]

    transitions: Transition {
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 1
                    to: 0.9
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
            }
            PropertyAction {
                target: root
                property: "delegate"
                value: null
            }
            ScriptAction {
                script: root.displayText = root.search.text
            }
            PropertyAction {
                target: root
                property: "delegate"
            }
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 0.9
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
            }
            PropertyAction {
                targets: [root.add, root.remove]
                property: "enabled"
                value: true
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            type: Anim.StandardSmall
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    displaced: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    Component {
        id: appItem

        AppItem {
            screenState: root.screenState
        }
    }

    Component {
        id: actionItem

        ActionItem {
            list: root
        }
    }

    Component {
        id: calcItem

        CalcItem {
            list: root
        }
    }

    Component {
        id: aiItem

        AiItem {
            list: root
        }
    }

    Component {
        id: sshItem

        ActionItem {
            list: root
        }
    }

    Component {
        id: browserItem

        BrowserItem {
            list: root
        }
    }

    Component {
        id: clipboardItem

        ClipboardItem {
            list: root
        }
    }

    Component {
        id: convertItem

        ConvertItem {
            list: root
        }
    }

    Connections {
        function onTextChanged() {
            root.syncDisplayText();
        }

        target: root.search
    }

    Connections {
        function onLauncherChanged() {
            root.syncDisplayText();
            if (root.screenState.launcher && root.requestedState === "clipboard")
                Clipboard.reload();
        }

        target: root.screenState
    }
}
