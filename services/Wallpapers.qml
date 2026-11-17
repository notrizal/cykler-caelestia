pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")
    readonly property list<string> validVideoExtensions: ["mp4", "webm", "mkv", "mov", "avi"]
    readonly property list<FileSystemEntry> staticList: staticWallpapers.entries
    readonly property list<FileSystemEntry> animatedList: animatedWallpapers.entries

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    property string wallpaperMode: "static"
    property string lastStatic: ""
    property string lastAnimated: ""
    property string cacheBuster: ""
    property var itemBusters: ({})
    property var _hashCache: ({})
    property bool extractingThumbs: false
    property bool _pendingForceRefresh: false
    property bool _initialised: false

    signal thumbExtracted(string path)

    function cleanPath(path: string): string {
        let clean = String(path || "").split(/[?#]/)[0];
        if (clean.startsWith("file://"))
            clean = clean.slice(7);
        return clean;
    }

    function djb2Hash(value: string): string {
        if (!value)
            return "0";
        if (_hashCache[value] !== undefined)
            return _hashCache[value];

        let h = 5381;
        for (let i = 0; i < value.length; i++) {
            h = ((h << 5) + h) + value.charCodeAt(i);
            h |= 0;
        }
        const res = (h >>> 0).toString(10);
        _hashCache[value] = res;
        return res;
    }

    function isVideo(path: string): bool {
        const clean = cleanPath(path).toLowerCase();
        if (!clean)
            return false;
        const dot = clean.lastIndexOf(".");
        if (dot < 0)
            return false;
        return validVideoExtensions.includes(clean.slice(dot + 1));
    }

    function thumbFilePath(path: string): string {
        const clean = cleanPath(path);
        if (!clean)
            return "";
        return `${Paths.cache}/videothumbs/${djb2Hash(clean)}.jpg`;
    }

    function getWallpaperThumb(path: string, buster: string): string {
        const file = thumbFilePath(path);
        if (!file)
            return "";
        const v = buster !== undefined && buster !== "" ? buster : cacheBuster;
        return `file://${file}${v ? `?v=${v}` : ""}`;
    }

    function thumbBusterFor(path: string): string {
        const clean = cleanPath(path);
        return itemBusters[clean] ?? cacheBuster;
    }

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setWallpaperMode(mode: string): void {
        if (mode === "static" || mode === "animated")
            wallpaperMode = mode;
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        const clean = cleanPath(path);
        if (!clean)
            return;

        actualCurrent = clean;
        if (isVideo(clean)) {
            lastAnimated = clean;
            wallpaperMode = "animated";
            Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/last_animated.txt\"", "_", `${Paths.state}/wallpaper`, clean]);
        } else {
            lastStatic = clean;
            wallpaperMode = "static";
            Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/last_static.txt\"", "_", `${Paths.state}/wallpaper`, clean]);
        }

        stopPreview();
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", clean, ...smartArg]);
    }

    function preview(path: string): void {
        const clean = cleanPath(path);
        if (!clean)
            return;

        previewPath = clean;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.startFor(clean);
    }

    function stopPreview(): void {
        showPreview = false;
        if (getPreviewColoursProc.running)
            getPreviewColoursProc.running = false;

        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    function refreshAnimatedThumbs(force: bool): void {
        if (extractingThumbs) {
            if (force)
                _pendingForceRefresh = true;
            return;
        }

        if (force)
            itemBusters = {};

        extractingThumbs = true;
        const cmd = [
            "python3",
            Quickshell.shellPath("scripts/caelestia-extract-videothumbs.py"),
            "--dir",
            Paths.wallsdir,
            "--cache-dir",
            `${Paths.cache}/videothumbs`
        ];
        if (force)
            cmd.push("--force");
        extractThumbsProc.wasForced = force;
        extractThumbsProc.command = cmd;
        extractThumbsProc.running = true;
    }

    list: wallpaperMode === "animated" ? animatedWallpapers.entries : staticWallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear) {
            pendingPreviewClear = false;
            Colours.showPreview = false;
        }
    }

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return [...staticWallpapers.entries, ...animatedWallpapers.entries].map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;

            if (root.isVideo(wall)) {
                if (!root.lastAnimated)
                    root.lastAnimated = wall;
                if (!root._initialised)
                    root.wallpaperMode = "animated";
            } else {
                if (!root.lastStatic)
                    root.lastStatic = wall;
                if (!root._initialised)
                    root.wallpaperMode = "static";
            }
            root._initialised = true;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            root._initialised = true;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileView {
        path: `${Paths.state}/wallpaper/last_static.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val)
                root.lastStatic = val;
        }
    }

    FileView {
        path: `${Paths.state}/wallpaper/last_animated.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val)
                root.lastAnimated = val;
        }
    }

    FileSystemModel {
        id: staticWallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    FileSystemModel {
        id: animatedWallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Videos
        onEntriesChanged: {
            if (entries.length > 0)
                autoExtractTimer.restart();
        }
    }

    Timer {
        id: autoExtractTimer

        interval: 250
        repeat: false
        onTriggered: {
            if (animatedWallpapers.entries.length > 0)
                root.refreshAnimatedThumbs(false);
        }
    }

    Process {
        id: getPreviewColoursProc

        property string currentProcessingPath: ""

        function startFor(path: string): void {
            if (!path)
                return;
            currentProcessingPath = path;
            if (running)
                running = false;
            running = true;
        }

        command: ["caelestia", "wallpaper", "-p", currentProcessingPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.showPreview)
                    return;

                const raw = text ? text.trim() : "";
                if (raw) {
                    try {
                        JSON.parse(raw);
                        Colours.load(raw, true);
                        Colours.showPreview = true;
                    } catch (e) {
                        // Ignore truncated output when interrupted by rapid scrolling
                    }
                }

                if (root.showPreview && root.previewPath && root.previewPath !== getPreviewColoursProc.currentProcessingPath)
                    getPreviewColoursProc.startFor(root.previewPath);
            }
        }
    }

    Process {
        id: extractThumbsProc

        property bool wasForced: false

        stdout: SplitParser {
            onRead: data => {
                const path = root.cleanPath(data.trim());
                if (!path)
                    return;

                const next = Object.assign({}, root.itemBusters);
                next[path] = Date.now().toString();
                root.itemBusters = next;
                root.thumbExtracted(path);
            }
        }

        onExited: {
            root.extractingThumbs = false;
            if (wasForced)
                root.cacheBuster = Date.now().toString();
            if (root._pendingForceRefresh) {
                root._pendingForceRefresh = false;
                root.refreshAnimatedThumbs(true);
            }
        }
    }
}
