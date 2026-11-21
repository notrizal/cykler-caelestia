pragma Singleton

import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils

Singleton {
    id: root

    readonly property string pinnedPath: `${Paths.state}/pinned-clips.json`
    readonly property string cacheDir: `${Paths.cache}/clipcache`
    readonly property var categories: [
        { key: "all", icon: "select_all", text: Tr.tr("All") },
        { key: "pinned", icon: "keep", text: Tr.tr("Pin") },
        { key: "image", icon: "image", text: Tr.tr("Images") },
        { key: "link", icon: "link", text: Tr.tr("Links") },
        { key: "code", icon: "code", text: Tr.tr("Code") },
        { key: "text", icon: "notes", text: Tr.tr("Text") }
    ]
    readonly property var terminalClasses: [
        "foot", "footclient", "kitty", "alacritty", "wezterm", "org.wezfurlong.wezterm",
        "ghostty", "com.mitchellh.ghostty", "konsole", "org.kde.konsole",
        "gnome-terminal", "org.gnome.console", "kgx", "xfce4-terminal",
        "terminator", "tilix", "urxvt", "xterm", "st", "rio", "warp", "tabby", "hyper"
    ]

    property var historyItems: []
    property var pinnedItems: []
    property var imagePaths: ({})
    property var decodeQueue: []
    property var decodingIds: ({})
    property var activeDecodeJob: null
    property string activeCategory: "all"
    property bool pinnedLoaded: false
    property int revision: 0
    property int imageRevision: 0

    readonly property int activeCategoryIndex: {
        const idx = categories.findIndex(c => c.key === activeCategory);
        return idx >= 0 ? idx : 0;
    }

    function reload(): void {
        listProc.running = false;
        listProc.running = true;
    }

    function setCategory(key: string): void {
        if (root.activeCategory === key)
            return;
        root.activeCategory = key;
        root.revision++;
    }

    function setCategoryIndex(index: int): void {
        const entry = root.categories[index];
        if (entry)
            setCategory(entry.key);
    }

    function cycleCategory(delta: int): void {
        const len = root.categories.length;
        if (len === 0)
            return;
        const nextIdx = (root.activeCategoryIndex + delta + len) % len;
        setCategory(root.categories[nextIdx].key);
    }

    function resetCategory(): void {
        if (root.activeCategory !== "all") {
            root.activeCategory = "all";
            root.revision++;
        }
    }

    function queryFromText(searchText: string): string {
        const prefix = `${GlobalConfig.launcher.actionPrefix}clip`;
        if (searchText.startsWith(`${prefix} `))
            return searchText.slice(`${prefix} `.length).trim();
        return "";
    }

    function extractHost(urlText: string): string {
        const m = urlText.match(/^https?:\/\/([^/\s?#]+)/i);
        return m ? m[1] : Tr.tr("URL");
    }

    function classifyText(preview: string): var {
        const trimmed = preview.trim();

        if (/^https?:\/\/\S+/i.test(trimmed)) {
            return {
                category: "link",
                icon: "link",
                desc: extractHost(trimmed),
                badgeLabel: "URL",
                badgeTone: "tertiary",
                swatch: "",
                isMonospace: false
            };
        }

        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(trimmed) || /^(rgb|rgba|hsl|hsla)\([^)]+\)$/i.test(trimmed)) {
            return {
                category: "text",
                icon: "palette",
                desc: Tr.tr("Colour"),
                badgeLabel: "COLOUR",
                badgeTone: "tertiary",
                swatch: trimmed,
                isMonospace: true
            };
        }

        if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
            return {
                category: "text",
                icon: "mail",
                desc: Tr.tr("Email"),
                badgeLabel: "EMAIL",
                badgeTone: "secondary",
                swatch: "",
                isMonospace: false
            };
        }

        if (/^(~\/|\/[^\s]+)/.test(trimmed)) {
            return {
                category: "code",
                icon: "folder_open",
                desc: Tr.tr("File path"),
                badgeLabel: "PATH",
                badgeTone: "secondary",
                swatch: "",
                isMonospace: true
            };
        }

        const looksLikeCode = /^(sudo |git |cd |ls |cp |mv |rm |mkdir |chmod |pacman |yay |paru |docker |kubectl |npm |pnpm |python3? |cargo |cmake |hyprctl |systemctl |journalctl |curl |ssh |export |const |let |var |function |class |def |import |from |#include|#!|SELECT |INSERT |UPDATE |DELETE )/i.test(trimmed)
            || (/^[\[{].*[\]}]$/.test(trimmed) && trimmed.includes(":"))
            || (/[{}();=<>]/.test(trimmed) && (trimmed.includes("=>") || trimmed.includes("::") || trimmed.includes("()") || trimmed.includes(";") || trimmed.includes("--")));
        if (looksLikeCode) {
            return {
                category: "code",
                icon: "code",
                desc: Tr.tr("Snippet · %1 chars").arg(trimmed.length),
                badgeLabel: "CODE",
                badgeTone: "secondary",
                swatch: "",
                isMonospace: true
            };
        }

        return {
            category: "text",
            icon: "notes",
            desc: Tr.tr("%1 chars").arg(trimmed.length),
            badgeLabel: "TEXT",
            badgeTone: "neutral",
            swatch: "",
            isMonospace: false
        };
    }

    function compactPreview(text: string): string {
        return String(text || "").replace(/\s+/g, " ").trim();
    }

    function parseHistory(rawOutput: string): var {
        const result = [];
        const lines = rawOutput.split("\n");
        const imgRe = /^\[\[\s*binary data\s+(.+?)\s+(png|jpe?g|webp|gif|bmp|avif|tiff?)\s+(\d+x\d+)\s*\]\]$/i;

        for (const line of lines) {
            if (!line)
                continue;
            const tabIdx = line.indexOf("\t");
            if (tabIdx <= 0)
                continue;

            const clipId = line.slice(0, tabIdx).trim();
            const preview = line.slice(tabIdx + 1);
            if (!clipId)
                continue;

            const imgMatch = preview.match(imgRe);
            if (imgMatch) {
                const sizeText = imgMatch[1].trim();
                const ext = imgMatch[2].toLowerCase();
                const dims = imgMatch[3].replace("x", "×");
                const itemObj = {
                    key: `hist:${clipId}`,
                    clipId: clipId,
                    rawLine: line,
                    category: "image",
                    isPinned: false,
                    isImage: true,
                    isClearAction: false,
                    isMonospace: false,
                    showSectionBreak: false,
                    imageExt: ext === "jpeg" ? "jpg" : ext,
                    name: Tr.tr("Image · %1").arg(dims),
                    desc: `${ext.toUpperCase()} · ${sizeText}`,
                    badgeLabel: ext.toUpperCase(),
                    badgeTone: "primary",
                    icon: "image",
                    swatch: "",
                    searchBlob: `image ${ext} ${dims} ${sizeText}`.toLowerCase(),
                    fullText: ""
                };
                itemObj.onClicked = list => root.activateItem(itemObj, list);
                result.push(itemObj);
            } else {
                const clean = compactPreview(preview);
                if (!clean)
                    continue;
                const meta = classifyText(clean);
                const itemObj = {
                    key: `hist:${clipId}`,
                    clipId: clipId,
                    rawLine: line,
                    category: meta.category,
                    isPinned: false,
                    isImage: false,
                    isClearAction: false,
                    isMonospace: meta.isMonospace,
                    showSectionBreak: false,
                    imageExt: "",
                    name: clean,
                    desc: meta.desc,
                    badgeLabel: meta.badgeLabel,
                    badgeTone: meta.badgeTone,
                    icon: meta.icon,
                    swatch: meta.swatch,
                    searchBlob: `${clean} ${meta.category} ${meta.badgeLabel} ${meta.desc}`.toLowerCase(),
                    fullText: ""
                };
                itemObj.onClicked = list => root.activateItem(itemObj, list);
                result.push(itemObj);
            }
        }
        return result;
    }

    function buildPinnedEntries(): var {
        const result = [];
        for (const entry of root.pinnedItems) {
            if (!entry || !entry.text)
                continue;
            const clean = compactPreview(entry.text);
            const meta = classifyText(clean);
            const entryId = String(entry.id);
            const fullText = String(entry.text);
            const itemObj = {
                key: `pin:${entryId}`,
                clipId: entryId,
                rawLine: "",
                category: meta.category,
                isPinned: true,
                isImage: false,
                isClearAction: false,
                isMonospace: meta.isMonospace,
                showSectionBreak: false,
                imageExt: "",
                name: clean,
                desc: Tr.tr("Pinned · %1").arg(meta.desc),
                badgeLabel: meta.badgeLabel,
                badgeTone: meta.badgeTone,
                icon: meta.icon,
                swatch: meta.swatch,
                searchBlob: `pinned ${clean} ${meta.category} ${meta.badgeLabel} ${meta.desc}`.toLowerCase(),
                fullText: fullText
            };
            itemObj.onClicked = list => root.activateItem(itemObj, list);
            result.push(itemObj);
        }
        return result;
    }

    function matchesCategory(item: var, cat: string): bool {
        if (cat === "all")
            return true;
        if (cat === "pinned")
            return item.isPinned;
        return item.category === cat;
    }

    function search(searchText: string): var {
        const q = queryFromText(searchText).toLowerCase();
        const pinned = buildPinnedEntries();
        const cat = root.activeCategory;

        const matchingPinned = pinned.filter(item => matchesCategory(item, cat) && (!q || item.searchBlob.includes(q)));
        const matchingHistory = root.historyItems
            .filter(item => matchesCategory(item, cat) && (!q || item.searchBlob.includes(q)))
            .map((item, idx) => {
                if (idx === 0 && matchingPinned.length > 0)
                    return Object.assign({}, item, { showSectionBreak: true });
                return item.showSectionBreak ? Object.assign({}, item, { showSectionBreak: false }) : item;
            });

        const filtered = [...matchingPinned, ...matchingHistory];

        if (root.historyItems.length > 0 && q && ("clear clipboard history wipe".includes(q) || q === "clear" || q === "wipe")) {
            return [
                ...filtered,
                {
                    key: "action:clear",
                    clipId: "",
                    rawLine: "",
                    category: "action",
                    isPinned: false,
                    isImage: false,
                    isClearAction: true,
                    isMonospace: false,
                    showSectionBreak: false,
                    imageExt: "",
                    name: Tr.tr("Clear clipboard history"),
                    desc: Tr.tr("Remove all unpinned clipboard items (%1)").arg(root.historyItems.length),
                    badgeLabel: "",
                    badgeTone: "neutral",
                    icon: "delete_sweep",
                    swatch: "",
                    searchBlob: "clear clipboard history wipe",
                    fullText: "",
                    onClicked: () => root.clearHistory()
                }
            ];
        }
        return filtered;
    }

    function ensureImagePreview(clipId: string, ext: string): void {
        if (!clipId || root.imagePaths[clipId] || root.decodingIds[clipId])
            return;

        root.decodingIds[clipId] = true;
        root.decodeQueue = [...root.decodeQueue, {
            clipId: clipId,
            ext: ext || "png"
        }];
        processDecodeQueue();
    }

    function processDecodeQueue(): void {
        if (decodeProc.running || root.decodeQueue.length === 0)
            return;

        const next = root.decodeQueue[0];
        root.decodeQueue = root.decodeQueue.slice(1);
        root.activeDecodeJob = next;

        const outPath = `${root.cacheDir}/${next.clipId}.${next.ext}`;
        decodeProc.command = [
            "sh", "-c",
            'mkdir -p "$1" && ([ -s "$2" ] || cliphist decode "$3" > "$2")',
            "_", root.cacheDir, outPath, next.clipId
        ];
        decodeProc.running = true;
    }

    function isFocusedTerminal(): bool {
        const ipc = Hypr.activeToplevel?.lastIpcObject;
        const cls = String(ipc?.class || "").toLowerCase();
        const initCls = String(ipc?.initialClass || "").toLowerCase();
        return root.terminalClasses.some(t => cls === t || initCls === t || cls.includes(t));
    }

    function triggerAutoPaste(): void {
        if (!GlobalConfig.launcher.clipboardAutoPaste || !Hypr.activeToplevel)
            return;

        if (isFocusedTerminal())
            Hypr.sendShortcut("CTRL + SHIFT", "V");
        else
            Hypr.sendShortcut("CTRL", "V");
    }

    function activateItem(item: var, list: var): void {
        if (!item)
            return;

        if (list?.screenState)
            list.screenState.launcher = false;

        pasteTimer.stop();
        copyProc.running = false;
        if (item.isPinned) {
            copyProc.command = ["sh", "-c", 'printf "%s" "$1" | wl-copy', "_", item.fullText];
        } else {
            copyProc.command = ["sh", "-c", 'cliphist decode "$1" | wl-copy', "_", item.clipId];
        }
        copyProc.running = true;
    }

    function togglePin(item: var): void {
        if (!item || item.isImage || item.isClearAction)
            return;

        if (item.isPinned) {
            root.pinnedItems = root.pinnedItems.filter(p => String(p.id) !== String(item.clipId));
            savePinned();
            root.revision++;
            return;
        }

        if (pinDecodeProc.running)
            pinDecodeProc.running = false;
        pinDecodeProc.command = ["cliphist", "decode", item.clipId];
        pinDecodeProc.running = true;
    }

    function deleteItem(item: var): void {
        if (!item || item.isClearAction)
            return;

        if (item.isPinned) {
            root.pinnedItems = root.pinnedItems.filter(p => String(p.id) !== String(item.clipId));
            savePinned();
            root.revision++;
            return;
        }

        root.historyItems = root.historyItems.filter(h => h.clipId !== item.clipId);
        root.revision++;
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "_", item.rawLine]);
    }

    function clearHistory(): void {
        root.historyItems = [];
        root.imagePaths = ({});
        root.decodingIds = ({});
        root.decodeQueue = [];
        root.revision++;
        root.imageRevision++;
        Quickshell.execDetached(["sh", "-c", 'cliphist wipe && rm -rf "$1"', "_", root.cacheDir]);
        Toaster.toast(Tr.tr("Clipboard cleared"), Tr.tr("Pinned snippets were kept"), "delete_sweep");
    }

    function savePinned(): void {
        if (root.pinnedLoaded)
            pinnedStorage.setText(JSON.stringify(root.pinnedItems, null, 2));
    }

    FileView {
        id: pinnedStorage

        path: root.pinnedPath
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.pinnedItems = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                root.pinnedItems = [];
            }
            root.pinnedLoaded = true;
            root.revision++;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.pinnedItems = [];
                root.pinnedLoaded = true;
            }
        }
    }

    Process {
        id: listProc

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.historyItems = root.parseHistory(text);
                root.revision++;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.historyItems = [];
                root.revision++;
            }
        }
    }

    Process {
        id: copyProc

        onExited: exitCode => {
            if (exitCode === 0 && GlobalConfig.launcher.clipboardAutoPaste)
                pasteTimer.restart();
        }
    }

    Timer {
        id: pasteTimer

        interval: 100
        repeat: false
        onTriggered: root.triggerAutoPaste()
    }

    Process {
        id: pinDecodeProc

        stdout: StdioCollector {
            onStreamFinished: {
                const full = text;
                if (!full || !full.trim())
                    return;
                if (root.pinnedItems.some(p => p.text === full))
                    return;

                root.pinnedItems = [{
                    id: String(Date.now()),
                    text: full
                }, ...root.pinnedItems];
                root.savePinned();
                root.revision++;
            }
        }
    }

    Process {
        id: decodeProc

        onExited: exitCode => {
            const job = root.activeDecodeJob;
            root.activeDecodeJob = null;
            if (job && exitCode === 0) {
                const nextMap = Object.assign({}, root.imagePaths);
                nextMap[job.clipId] = `file://${root.cacheDir}/${job.clipId}.${job.ext}`;
                root.imagePaths = nextMap;
                root.imageRevision++;
            } else if (job) {
                delete root.decodingIds[job.clipId];
            }
            root.processDecodeQueue();
        }
    }
}
