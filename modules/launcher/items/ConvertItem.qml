pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property var list

    property string openDropdown: ""

    readonly property string query: {
        const text = list?.search?.text ?? "";
        const prefix = `${GlobalConfig.launcher.actionPrefix}convert`;
        if (text.startsWith(`${prefix} `))
            return text.slice(prefix.length + 1).trim();
        return "";
    }
    readonly property string directPathCandidate: {
        const q = root.query;
        if (q.startsWith("~/"))
            return `${Paths.home}/${q.slice(2)}`;
        if (q.startsWith("/"))
            return q;
        return "";
    }
    readonly property var activeDropdownSpec: {
        switch (openDropdown) {
        case "targetKey":
            return { title: Tr.tr("Convert To"), options: Converter.availableTargets, currentKey: Converter.targetKey, columns: 2 };
        case "imgQuality":
            return { title: Tr.tr("Image Quality"), options: Converter.imageQualities, currentKey: Converter.imgQuality, columns: 2 };
        case "imgResize":
            return { title: Tr.tr("Resize"), options: Converter.imageResizes, currentKey: Converter.imgResize, columns: 3 };
        case "imgRotate":
            return { title: Tr.tr("Rotate"), options: Converter.imageRotations, currentKey: Converter.imgRotate, columns: 2 };
        case "vidQuality":
            return { title: Tr.tr("Video Quality"), options: Converter.videoQualities, currentKey: Converter.vidQuality, columns: 2 };
        case "vidResolution":
            return { title: Tr.tr("Resolution"), options: Converter.videoResolutions, currentKey: Converter.vidResolution, columns: 2 };
        case "vidFps":
            return { title: Tr.tr("Frame Rate"), options: Converter.videoFpsOptions, currentKey: Converter.vidFps, columns: 2 };
        case "audBitrate":
            return { title: Tr.tr("Audio Bitrate"), options: Converter.audioBitrates, currentKey: Converter.audBitrate, columns: 3 };
        case "audSampleRate":
            return { title: Tr.tr("Sample Rate"), options: Converter.audioSampleRates, currentKey: Converter.audSampleRate, columns: 3 };
        case "docQuality":
            return { title: Converter.targetKey === "pdf_compress" ? Tr.tr("Compression Preset") : Tr.tr("Image Quality (DPI)"), options: Converter.docQualities, currentKey: Converter.docQuality, columns: 3 };
        default:
            return null;
        }
    }

    function toggleDropdown(id: string): void {
        root.openDropdown = root.openDropdown === id ? "" : id;
    }

    function applyDropdownSelection(key: string): void {
        switch (root.openDropdown) {
        case "targetKey":
            Converter.targetKey = key;
            break;
        case "imgQuality":
            Converter.imgQuality = key;
            break;
        case "imgResize":
            Converter.imgResize = key;
            break;
        case "imgRotate":
            Converter.imgRotate = key;
            break;
        case "vidQuality":
            Converter.vidQuality = key;
            break;
        case "vidResolution":
            Converter.vidResolution = key;
            break;
        case "vidFps":
            Converter.vidFps = key;
            break;
        case "audBitrate":
            Converter.audBitrate = key;
            break;
        case "audSampleRate":
            Converter.audSampleRate = key;
            break;
        case "docQuality":
            Converter.docQuality = key;
            break;
        }
        root.openDropdown = "";
    }

    function onClicked(): void {
        if (Converter.busy)
            return;
        if (Converter.selectedPath) {
            Converter.startConvert();
            return;
        }
        if (root.directPathCandidate) {
            Converter.selectFile(root.directPathCandidate, 0);
            return;
        }
        Converter.openFileDialog(root.list?.screenState);
    }

    function iconForKind(kind: string): string {
        if (kind === "image")
            return "image";
        if (kind === "video")
            return "movie";
        if (kind === "audio")
            return "music_note";
        if (kind === "pdf")
            return "picture_as_pdf";
        if (kind === "office")
            return "description";
        return "sync_alt";
    }

    width: (list?.width ?? 0) > 0 ? list.width : Tokens.sizes.launcher.itemWidth
    implicitHeight: mainCol.implicitHeight + Tokens.padding.small * 2

    Connections {
        function onSelectedPathChanged(): void {
            root.openDropdown = "";
        }

        target: Converter
    }

    DropArea {
        id: dropArea

        anchors.fill: parent
        onDropped: drop => {
            if (drop.hasUrls && drop.urls.length > 0) {
                Converter.selectFile(drop.urls[0].toString(), 0);
                drop.accept();
            } else if (drop.hasText && drop.text.trim().length > 0) {
                const firstLine = drop.text.trim().split("\n")[0].trim();
                Converter.selectFile(firstLine, 0);
                drop.accept();
            }
        }
    }

    ColumnLayout {
        id: mainCol

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.small
        spacing: Tokens.spacing.small

        // 1. Source File Card (File-first Dropzone / Selected File Info)
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: sourceCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: dropArea.containsDrag ? Qt.alpha(Colours.palette.m3primary, 0.14) : Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: sourceCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                // Empty state: clean file-first Browse & Drag-Drop card
                RowLayout {
                    Layout.fillWidth: true
                    visible: Converter.selectedPath === ""
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Tokens.rounding.medium
                        color: Colours.tPalette.m3surfaceContainerHigh

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: dropArea.containsDrag ? "upload_file" : "sync_alt"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.large
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: dropArea.containsDrag ? Tr.tr("Drop file here to detect & convert") : Tr.tr("Select or drop a file to convert")
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Converter.errorText ? Converter.errorText : Tr.tr("Auto-detects Images, Video, Audio, PDF & Office documents")
                            color: Converter.errorText ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconTextButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon: "folder_open"
                        text: Tr.tr("Browse...")
                        font: Tokens.font.label.medium
                        isRound: true
                        horizontalPadding: Tokens.padding.medium
                        verticalPadding: Tokens.padding.small
                        type: IconTextButton.Filled
                        onClicked: Converter.openFileDialog(root.list?.screenState)
                    }
                }

                // Direct path quick-select banner if user typed ~/... or /...
                StyledRect {
                    Layout.fillWidth: true
                    visible: Converter.selectedPath === "" && root.directPathCandidate !== ""
                    implicitHeight: 36
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3secondaryContainer

                    StateLayer {
                        color: Colours.palette.m3onSecondaryContainer
                        radius: parent.radius
                        onClicked: Converter.selectFile(root.directPathCandidate, 0)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "file_open"
                            color: Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Tr.tr("Use path: %1").arg(Paths.shortenHome(root.directPathCandidate))
                            color: Colours.palette.m3onSecondaryContainer
                            font: Tokens.font.label.medium
                            elide: Text.ElideMiddle
                        }
                    }
                }

                // Selected file row with auto-detected type badge
                RowLayout {
                    Layout.fillWidth: true
                    visible: Converter.selectedPath !== ""
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3primaryContainer
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: Converter.selectedKind === "image" && status === Image.Ready
                            source: Converter.selectedKind === "image" && Converter.selectedPath ? `file://${Converter.selectedPath}` : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize.width: 96
                            sourceSize.height: 96
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: Converter.selectedKind !== "image"
                            text: root.iconForKind(Converter.selectedKind)
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.large
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                Layout.fillWidth: true
                                text: Converter.selectedName
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                                elide: Text.ElideMiddle
                            }

                            StyledRect {
                                visible: Converter.detectedTypeLabel !== ""
                                implicitWidth: selTypeText.implicitWidth + Tokens.padding.small * 2
                                implicitHeight: selTypeText.implicitHeight + 4
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3primaryContainer

                                StyledText {
                                    id: selTypeText

                                    anchors.centerIn: parent
                                    text: Converter.detectedTypeLabel
                                    color: Colours.palette.m3onPrimaryContainer
                                    font: Tokens.font.label.small
                                }
                            }

                            StyledRect {
                                visible: Converter.selectedSize !== ""
                                implicitWidth: selSizeText.implicitWidth + Tokens.padding.small * 2
                                implicitHeight: selSizeText.implicitHeight + 4
                                radius: Tokens.rounding.small
                                color: Colours.tPalette.m3surfaceContainerHigh

                                StyledText {
                                    id: selSizeText

                                    anchors.centerIn: parent
                                    text: Converter.selectedSize
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Paths.shortenHome(Converter.selectedDir)
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideMiddle
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        type: IconButton.Tonal
                        icon: "folder_open"
                        isRound: true
                        onClicked: Converter.openFileDialog(root.list?.screenState)
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        type: IconButton.Tonal
                        icon: "close"
                        isRound: true
                        onClicked: Converter.clearSelection()
                    }
                }
            }
        }

        // 2. Dynamic Conversion Options Card (Only visible after a file is selected & detected)
        StyledRect {
            Layout.fillWidth: true
            visible: Converter.selectedPath !== ""
            implicitHeight: settingsCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: settingsCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                // --- IMAGE FILE DETECTED ---
                GridLayout {
                    Layout.fillWidth: true
                    visible: Converter.selectedKind === "image"
                    columns: 2
                    columnSpacing: Tokens.spacing.small
                    rowSpacing: Tokens.spacing.small

                    DropdownField {
                        Layout.fillWidth: true
                        fieldId: "targetKey"
                        icon: "transform"
                        label: Tr.tr("Convert to")
                        valueText: Converter.labelForOption(Converter.availableTargets, Converter.targetKey)
                    }

                    DropdownField {
                        Layout.fillWidth: true
                        visible: Converter.targetKey !== "png" && Converter.targetKey !== "ico"
                        fieldId: "imgQuality"
                        icon: "tune"
                        label: Tr.tr("Quality")
                        valueText: Converter.labelForOption(Converter.imageQualities, Converter.imgQuality)
                    }

                    DropdownField {
                        Layout.fillWidth: true
                        visible: Converter.targetKey !== "ico"
                        fieldId: "imgResize"
                        icon: "photo_size_select_large"
                        label: Tr.tr("Resize")
                        valueText: Converter.labelForOption(Converter.imageResizes, Converter.imgResize)
                    }

                    DropdownField {
                        Layout.fillWidth: true
                        fieldId: "imgRotate"
                        icon: "rotate_right"
                        label: Tr.tr("Rotate")
                        valueText: Converter.labelForOption(Converter.imageRotations, Converter.imgRotate)
                    }

                    ToggleField {
                        Layout.fillWidth: true
                        Layout.columnSpan: (Converter.targetKey !== "png" && Converter.targetKey !== "ico") ? 2 : 1
                        icon: "cleaning_services"
                        label: Tr.tr("Remove Metadata")
                        active: Converter.imgStripExif
                        onToggled: Converter.imgStripExif = !Converter.imgStripExif
                    }
                }

                // --- VIDEO FILE DETECTED ---
                GridLayout {
                    Layout.fillWidth: true
                    visible: Converter.selectedKind === "video"
                    columns: 2
                    columnSpacing: Tokens.spacing.small
                    rowSpacing: Tokens.spacing.small

                    DropdownField {
                        Layout.fillWidth: true
                        fieldId: "targetKey"
                        icon: "transform"
                        label: Tr.tr("Convert to")
                        valueText: Converter.labelForOption(Converter.availableTargets, Converter.targetKey)
                    }

                    // Video compression quality (for MP4 / WebM / MKV)
                    DropdownField {
                        Layout.fillWidth: true
                        visible: Converter.targetKey !== "mp3" && Converter.targetKey !== "wav" && Converter.targetKey !== "gif"
                        fieldId: "vidQuality"
                        icon: "tune"
                        label: Tr.tr("Quality")
                        valueText: Converter.labelForOption(Converter.videoQualities, Converter.vidQuality)
                    }

                    // Audio bitrate when extracting MP3 from video
                    DropdownField {
                        Layout.fillWidth: true
                        visible: Converter.targetKey === "mp3"
                        fieldId: "audBitrate"
                        icon: "equalizer"
                        label: Tr.tr("Bitrate")
                        valueText: Converter.labelForOption(Converter.audioBitrates, Converter.audBitrate)
                    }

                    DropdownField {
                        Layout.fillWidth: true
                        visible: Converter.targetKey !== "mp3" && Converter.targetKey !== "wav"
                        fieldId: "vidResolution"
                        icon: "aspect_ratio"
                        label: Tr.tr("Scale")
                        valueText: Converter.labelForOption(Converter.videoResolutions, Converter.vidResolution)
                    }

                    DropdownField {
                        Layout.fillWidth: true
                        visible: Converter.targetKey !== "mp3" && Converter.targetKey !== "wav"
                        fieldId: "vidFps"
                        icon: "speed"
                        label: Tr.tr("FPS")
                        valueText: Converter.labelForOption(Converter.videoFpsOptions, Converter.vidFps)
                    }

                    ToggleField {
                        Layout.fillWidth: true
                        Layout.columnSpan: 2
                        visible: Converter.targetKey !== "mp3" && Converter.targetKey !== "wav" && Converter.targetKey !== "gif"
                        icon: Converter.vidMute ? "volume_off" : "volume_up"
                        label: Tr.tr("Mute Audio")
                        active: Converter.vidMute
                        onToggled: Converter.vidMute = !Converter.vidMute
                    }

                    ToggleField {
                        Layout.fillWidth: true
                        Layout.columnSpan: Converter.targetKey === "mp3" ? 2 : 1
                        visible: Converter.targetKey === "mp3" || Converter.targetKey === "wav"
                        icon: "graphic_eq"
                        label: Tr.tr("Normalize Volume")
                        active: Converter.audNormalize
                        onToggled: Converter.audNormalize = !Converter.audNormalize
                    }
                }

                // --- AUDIO FILE DETECTED ---
                GridLayout {
                    Layout.fillWidth: true
                    visible: Converter.selectedKind === "audio"
                    columns: 2
                    columnSpacing: Tokens.spacing.small
                    rowSpacing: Tokens.spacing.small

                    DropdownField {
                        Layout.fillWidth: true
                        fieldId: "targetKey"
                        icon: "transform"
                        label: Tr.tr("Convert to")
                        valueText: Converter.labelForOption(Converter.availableTargets, Converter.targetKey)
                    }

                    DropdownField {
                        Layout.fillWidth: true
                        visible: Converter.targetKey !== "wav" && Converter.targetKey !== "flac"
                        fieldId: "audBitrate"
                        icon: "equalizer"
                        label: Tr.tr("Bitrate")
                        valueText: Converter.labelForOption(Converter.audioBitrates, Converter.audBitrate)
                    }

                    DropdownField {
                        Layout.fillWidth: true
                        fieldId: "audSampleRate"
                        icon: "waves"
                        label: Tr.tr("Sample Rate")
                        valueText: Converter.labelForOption(Converter.audioSampleRates, Converter.audSampleRate)
                    }

                    ToggleField {
                        Layout.fillWidth: true
                        Layout.columnSpan: (Converter.targetKey === "wav" || Converter.targetKey === "flac") ? 2 : 1
                        icon: "graphic_eq"
                        label: Tr.tr("Normalize Volume")
                        active: Converter.audNormalize
                        onToggled: Converter.audNormalize = !Converter.audNormalize
                    }
                }

                // --- PDF OR OFFICE DOCUMENT DETECTED ---
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Converter.selectedKind === "pdf" || Converter.selectedKind === "office"
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        DropdownField {
                            Layout.fillWidth: true
                            fieldId: "targetKey"
                            icon: "transform"
                            label: Tr.tr("Convert to")
                            valueText: Converter.labelForOption(Converter.availableTargets, Converter.targetKey)
                        }

                        DropdownField {
                            Layout.fillWidth: true
                            visible: Converter.selectedKind === "pdf" && (Converter.targetKey === "pdf_compress" || Converter.targetKey === "pdf_png" || Converter.targetKey === "pdf_jpg")
                            fieldId: "docQuality"
                            icon: "tune"
                            label: Converter.targetKey === "pdf_compress" ? Tr.tr("Preset") : Tr.tr("DPI")
                            valueText: Converter.labelForOption(Converter.docQualities, Converter.docQuality)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: Converter.selectedKind === "pdf" && (Converter.targetKey === "pdf_png" || Converter.targetKey === "pdf_jpg")
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Tr.tr("Pages")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Tokens.rounding.full
                            color: Colours.tPalette.m3surfaceContainerHigh

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 3
                                spacing: Tokens.spacing.extraSmall

                                Repeater {
                                    model: Converter.docPageRanges

                                    StyledRect {
                                        id: pageSeg

                                        required property var modelData
                                        readonly property bool selected: Converter.docPages === modelData.key

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: Tokens.rounding.full
                                        color: selected ? Colours.palette.m3primary : "transparent"

                                        StateLayer {
                                            color: pageSeg.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                            radius: parent.radius
                                            onClicked: Converter.docPages = pageSeg.modelData.key
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: pageSeg.modelData.label
                                            color: pageSeg.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                            font: Tokens.font.label.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- INLINE EXPANDING DROPDOWN TRAY ---
                StyledRect {
                    id: dropdownTray

                    readonly property bool isOpen: root.activeDropdownSpec !== null

                    Layout.fillWidth: true
                    visible: implicitHeight > 1
                    implicitHeight: isOpen ? (trayCol.implicitHeight + Tokens.padding.small * 2) : 0
                    opacity: isOpen ? 1 : 0
                    clip: true
                    radius: Tokens.rounding.medium
                    color: Colours.tPalette.m3surfaceContainerHigh

                    Behavior on implicitHeight {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }

                    ColumnLayout {
                        id: trayCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.padding.small
                        spacing: Tokens.spacing.extraSmall

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                Layout.fillWidth: true
                                text: root.activeDropdownSpec?.title ?? ""
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StyledRect {
                                implicitWidth: 22
                                implicitHeight: 22
                                radius: Tokens.rounding.full
                                color: "transparent"

                                StateLayer {
                                    color: Colours.palette.m3onSurface
                                    radius: parent.radius
                                    onClicked: root.openDropdown = ""
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "close"
                                    color: Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.small
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: root.activeDropdownSpec?.columns ?? 2
                            columnSpacing: Tokens.spacing.extraSmall
                            rowSpacing: Tokens.spacing.extraSmall

                            Repeater {
                                model: root.activeDropdownSpec?.options ?? []

                                StyledRect {
                                    id: optItem

                                    required property var modelData
                                    readonly property bool isSelected: (root.activeDropdownSpec?.currentKey ?? "") === modelData.key

                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: Tokens.rounding.small
                                    color: isSelected ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
                                    clip: true

                                    StateLayer {
                                        color: optItem.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                        radius: parent.radius
                                        onClicked: root.applyDropdownSelection(optItem.modelData.key)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Tokens.padding.small
                                        anchors.rightMargin: Tokens.padding.small
                                        spacing: 4

                                        MaterialIcon {
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: optItem.isSelected
                                            text: "check"
                                            color: Colours.palette.m3onPrimary
                                            fontStyle: Tokens.font.icon.small
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: optItem.modelData.label ?? ""
                                            color: optItem.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                            font: Tokens.font.label.small
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Action & Status Footer Card (Only visible after a file is selected)
        StyledRect {
            Layout.fillWidth: true
            visible: Converter.selectedPath !== ""
            implicitHeight: footerRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Converter.errorText ? Qt.alpha(Colours.palette.m3error, 0.14) : Converter.lastOutputPath ? Qt.alpha(Colours.palette.m3primary, 0.12) : Colours.tPalette.m3surfaceContainer

            RowLayout {
                id: footerRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    id: footerIcon

                    Layout.alignment: Qt.AlignVCenter
                    text: Converter.errorText ? "error" : Converter.busy ? "autorenew" : Converter.lastOutputPath ? "check_circle" : "east"
                    color: Converter.errorText ? Colours.palette.m3error : (Converter.lastOutputPath || Converter.busy) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                    rotation: 0

                    RotationAnimator {
                        target: footerIcon
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        running: Converter.busy
                        onRunningChanged: {
                            if (!running)
                                footerIcon.rotation = 0;
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: {
                        if (Converter.errorText)
                            return Converter.errorText;
                        if (Converter.busy)
                            return Converter.statusText || Tr.tr("Converting...");
                        if (Converter.statusText)
                            return Converter.statusText;
                        if (Converter.previewOutputName)
                            return Tr.tr("Output: %1").arg(Converter.previewOutputName);
                        return "";
                    }
                    color: Converter.errorText ? Colours.palette.m3error : Colours.palette.m3onSurface
                    font: Tokens.font.label.medium
                    elide: Text.ElideMiddle
                }

                IconButton {
                    visible: !Converter.busy && Converter.lastOutputPath !== ""
                    type: IconButton.Tonal
                    icon: "open_in_new"
                    isRound: true
                    onClicked: Quickshell.execDetached(["xdg-open", Converter.lastOutputPath])
                }

                IconButton {
                    visible: !Converter.busy && Converter.lastOutputPath !== ""
                    type: IconButton.Tonal
                    icon: "folder_open"
                    isRound: true
                    onClicked: {
                        const slashIdx = Converter.lastOutputPath.lastIndexOf("/");
                        const folder = slashIdx > 0 ? Converter.lastOutputPath.slice(0, slashIdx) : Paths.home;
                        Quickshell.execDetached(["xdg-open", folder]);
                    }
                }

                IconButton {
                    visible: !Converter.busy && Converter.lastOutputPath !== ""
                    type: IconButton.Tonal
                    icon: "content_copy"
                    isRound: true
                    onClicked: Quickshell.execDetached(["wl-copy", Converter.lastOutputPath])
                }

                IconTextButton {
                    icon: Converter.busy ? "stop" : "bolt"
                    text: Converter.busy ? Tr.tr("Cancel") : Tr.tr("Convert")
                    disabled: !Converter.busy && Converter.selectedPath === ""
                    font: Tokens.font.label.medium
                    isRound: true
                    horizontalPadding: Tokens.padding.medium
                    verticalPadding: Tokens.padding.small
                    type: Converter.busy ? IconTextButton.Tonal : IconTextButton.Filled
                    onClicked: {
                        if (Converter.busy)
                            Converter.cancelConvert();
                        else
                            Converter.startConvert();
                    }
                }
            }
        }
    }

    component DropdownField: StyledRect {
        id: fieldRoot

        required property string fieldId
        required property string icon
        required property string label
        required property string valueText

        readonly property bool isOpen: root.openDropdown === fieldId

        implicitHeight: 40
        radius: Tokens.rounding.medium
        color: isOpen ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
        clip: true

        StateLayer {
            color: fieldRoot.isOpen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            radius: parent.radius
            onClicked: root.toggleDropdown(fieldRoot.fieldId)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: fieldRoot.icon
                color: fieldRoot.isOpen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: fieldRoot.label
                color: fieldRoot.isOpen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: fieldRoot.valueText
                color: fieldRoot.isOpen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
                elide: Text.ElideRight
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "expand_more"
                color: fieldRoot.isOpen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                rotation: fieldRoot.isOpen ? 180 : 0

                Behavior on rotation {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }

    component ToggleField: StyledRect {
        id: toggleRoot

        required property string icon
        required property string label
        required property bool active

        signal toggled

        implicitHeight: 40
        radius: Tokens.rounding.medium
        color: active ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
        clip: true

        StateLayer {
            color: toggleRoot.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            radius: parent.radius
            onClicked: toggleRoot.toggled()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: toggleRoot.icon
                color: toggleRoot.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                fill: toggleRoot.active ? 1 : 0
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: toggleRoot.label
                color: toggleRoot.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }

            StyledRect {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 32
                implicitHeight: 18
                radius: Tokens.rounding.full
                color: toggleRoot.active ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                StyledRect {
                    x: toggleRoot.active ? parent.width - width - 3 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    radius: Tokens.rounding.full
                    color: toggleRoot.active ? Colours.palette.m3onPrimary : Colours.palette.m3surface

                    Behavior on x {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }
                }
            }
        }
    }
}
