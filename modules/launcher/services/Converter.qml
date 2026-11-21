pragma Singleton

import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components.filedialog
import qs.services
import qs.utils

Singleton {
    id: root

    readonly property var imageExts: ["png", "jpg", "jpeg", "webp", "avif", "gif", "bmp", "tiff", "tif", "ico", "svg", "heic", "heif"]
    readonly property var videoExts: ["mp4", "mkv", "webm", "mov", "avi", "flv", "wmv", "m4v", "ts", "ogv", "3gp"]
    readonly property var audioExts: ["mp3", "wav", "flac", "ogg", "m4a", "aac", "opus", "wma", "aiff"]
    readonly property var officeExts: ["docx", "doc", "odt", "pptx", "ppt", "odp", "xlsx", "xls", "ods", "md", "markdown", "rst", "html", "htm", "txt", "rtf", "epub", "tex"]
    readonly property var allSupportedExts: ["pdf", ...imageExts, ...videoExts, ...audioExts, ...officeExts]

    readonly property var imageQualities: [
        { key: "lossless", label: Tr.tr("Lossless"), value: 100 },
        { key: "high", label: Tr.tr("High"), value: 90 },
        { key: "balanced", label: Tr.tr("Balanced"), value: 78 },
        { key: "small", label: Tr.tr("Small File"), value: 60 }
    ]
    readonly property var imageResizes: [
        { key: "original", label: Tr.tr("Original") },
        { key: "1920", label: Tr.tr("Full HD (1920px)") },
        { key: "1280", label: Tr.tr("HD (1280px)") },
        { key: "75%", label: "75%" },
        { key: "50%", label: "50%" }
    ]
    readonly property var imageRotations: [
        { key: "0", label: Tr.tr("None") },
        { key: "90", label: Tr.tr("90° Right") },
        { key: "180", label: "180°" },
        { key: "270", label: Tr.tr("90° Left") }
    ]

    readonly property var videoQualities: [
        { key: "high", label: Tr.tr("Best Quality"), crf: 18 },
        { key: "balanced", label: Tr.tr("Balanced"), crf: 23 },
        { key: "compact", label: Tr.tr("Smaller File"), crf: 28 },
        { key: "tiny", label: Tr.tr("Tiny (Chat / WA)"), crf: 33 }
    ]
    readonly property var videoResolutions: [
        { key: "original", label: Tr.tr("Original") },
        { key: "1080", label: Tr.tr("1080p (Full HD)") },
        { key: "720", label: Tr.tr("720p (HD)") },
        { key: "480", label: Tr.tr("480p (Compact)") }
    ]
    readonly property var videoFpsOptions: [
        { key: "original", label: Tr.tr("Original FPS") },
        { key: "60", label: "60 FPS" },
        { key: "30", label: "30 FPS" },
        { key: "15", label: "15 FPS" }
    ]

    readonly property var audioBitrates: [
        { key: "320k", label: Tr.tr("Best (320k)") },
        { key: "256k", label: Tr.tr("High (256k)") },
        { key: "192k", label: Tr.tr("Standard (192k)") },
        { key: "128k", label: Tr.tr("Compact (128k)") },
        { key: "96k", label: Tr.tr("Voice (96k)") }
    ]
    readonly property var audioSampleRates: [
        { key: "original", label: Tr.tr("Original") },
        { key: "48000", label: Tr.tr("48 kHz (Video)") },
        { key: "44100", label: Tr.tr("44.1 kHz (CD)") }
    ]

    readonly property var docQualities: [
        { key: "screen", label: Tr.tr("Smallest (Screen)"), gs: "/screen", dpi: 72 },
        { key: "ebook", label: Tr.tr("Balanced"), gs: "/ebook", dpi: 150 },
        { key: "printer", label: Tr.tr("Sharp (Print)"), gs: "/printer", dpi: 300 }
    ]
    readonly property var docPageRanges: [
        { key: "all", label: Tr.tr("All Pages") },
        { key: "first", label: Tr.tr("First Page Only") }
    ]

    property bool hasPdftotext: true
    property bool hasSoffice: false
    property bool hasPandoc: false
    property bool hasPdf2docx: false

    property string selectedPath: ""
    property string selectedName: ""
    property string selectedDir: ""
    property string selectedExt: ""
    property string selectedSize: ""
    property real selectedSizeBytes: 0
    // "image" | "video" | "audio" | "pdf" | "office" | ""
    property string selectedKind: ""
    property string targetKey: ""

    property string imgQuality: "high"
    property string imgResize: "original"
    property string imgRotate: "0"
    property bool imgStripExif: true

    property string vidQuality: "balanced"
    property string vidResolution: "original"
    property string vidFps: "original"
    property bool vidMute: false

    property string audBitrate: "192k"
    property string audSampleRate: "original"
    property bool audNormalize: false

    property string docQuality: "ebook"
    property string docPages: "all"

    property bool busy: false
    property string statusText: ""
    property string errorText: ""
    property string lastOutputPath: ""
    property string lastOutputName: ""
    property string lastOutputSize: ""
    property var pendingScreenState: null
    property int revision: 0

    readonly property string detectedTypeLabel: {
        if (!selectedExt)
            return "";
        const upper = selectedExt.toUpperCase();
        if (selectedKind === "image")
            return Tr.tr("%1 Image").arg(upper);
        if (selectedKind === "video")
            return Tr.tr("%1 Video").arg(upper);
        if (selectedKind === "audio")
            return Tr.tr("%1 Audio").arg(upper);
        if (selectedKind === "pdf")
            return Tr.tr("PDF Document");
        if (selectedKind === "office")
            return Tr.tr("%1 Document").arg(upper);
        return upper;
    }

    readonly property var availableTargets: {
        const ext = selectedExt.toLowerCase();
        const normExt = ext === "jpeg" ? "jpg" : ext;

        if (selectedKind === "image") {
            return [
                { key: "webp", ext: "webp", label: normExt === "webp" ? Tr.tr("WEBP (Compress / Resize)") : Tr.tr("WEBP (Smallest)") },
                { key: "png", ext: "png", label: normExt === "png" ? Tr.tr("PNG (Resize / Clean)") : Tr.tr("PNG (Lossless)") },
                { key: "jpg", ext: "jpg", label: normExt === "jpg" ? Tr.tr("JPG (Compress / Resize)") : Tr.tr("JPG (Universal)") },
                { key: "avif", ext: "avif", label: normExt === "avif" ? Tr.tr("AVIF (Compress / Resize)") : Tr.tr("AVIF (Modern)") },
                { key: "ico", ext: "ico", label: Tr.tr("ICO (256×256 Icon)") },
                { key: "pdf", ext: "pdf", label: Tr.tr("PDF (Document)") }
            ];
        }

        if (selectedKind === "video") {
            return [
                { key: "mp4", ext: "mp4", label: normExt === "mp4" ? Tr.tr("MP4 (Compress / Resize)") : Tr.tr("MP4 (Universal)") },
                { key: "webm", ext: "webm", label: normExt === "webm" ? Tr.tr("WebM (Compress / Resize)") : Tr.tr("WebM (Web)") },
                { key: "mkv", ext: "mkv", label: normExt === "mkv" ? Tr.tr("MKV (Re-encode)") : "MKV" },
                { key: "gif", ext: "gif", label: Tr.tr("GIF (Animated)") },
                { key: "mp3", ext: "mp3", label: Tr.tr("MP3 (Extract Audio)") },
                { key: "wav", ext: "wav", label: Tr.tr("WAV (Extract Audio)") }
            ];
        }

        if (selectedKind === "audio") {
            return [
                { key: "mp3", ext: "mp3", label: normExt === "mp3" ? Tr.tr("MP3 (Compress / Normalize)") : Tr.tr("MP3 (Universal)") },
                { key: "flac", ext: "flac", label: Tr.tr("FLAC (Lossless)") },
                { key: "wav", ext: "wav", label: Tr.tr("WAV (Uncompressed)") },
                { key: "ogg", ext: "ogg", label: "OGG (Vorbis)" },
                { key: "m4a", ext: "m4a", label: Tr.tr("M4A (AAC)") }
            ];
        }

        if (selectedKind === "pdf") {
            const list = [
                { key: "pdf_compress", ext: "pdf", label: Tr.tr("PDF (Compress Size)") },
                { key: "pdf_docx", ext: "docx", label: Tr.tr("DOCX (Word Document)") },
                { key: "pdf_png", ext: "png", label: Tr.tr("PNG (Page Images)") },
                { key: "pdf_jpg", ext: "jpg", label: Tr.tr("JPG (Page Images)") }
            ];
            if (root.hasPdftotext)
                list.push({ key: "pdf_txt", ext: "txt", label: Tr.tr("TXT (Extract Text)") });
            return list;
        }

        if (selectedKind === "office") {
            const list = [
                { key: "to_pdf", ext: "pdf", label: Tr.tr("PDF (Document)") }
            ];
            if (normExt !== "docx")
                list.push({ key: "to_docx", ext: "docx", label: Tr.tr("DOCX (Word Document)") });
            if (normExt !== "txt" && (root.hasSoffice || root.hasPandoc))
                list.push({ key: "to_txt", ext: "txt", label: Tr.tr("TXT (Plain Text)") });
            if (normExt !== "html" && normExt !== "htm" && (root.hasSoffice || root.hasPandoc))
                list.push({ key: "to_html", ext: "html", label: Tr.tr("HTML (Web Page)") });
            if (normExt !== "md" && normExt !== "markdown" && root.hasPandoc)
                list.push({ key: "to_md", ext: "md", label: Tr.tr("MD (Markdown)") });
            return list;
        }

        return [];
    }

    readonly property string targetExtension: {
        const found = availableTargets.find(t => t.key === targetKey);
        return found ? found.ext : "pdf";
    }

    readonly property string previewOutputName: {
        if (!selectedName || !targetKey)
            return "";
        const dotIdx = selectedName.lastIndexOf(".");
        const stem = dotIdx > 0 ? selectedName.slice(0, dotIdx) : selectedName;
        const ext = targetExtension;
        if (selectedKind === "pdf" && targetKey === "pdf_compress")
            return `${stem}_compressed.pdf`;
        if (selectedKind === "pdf" && (targetKey === "pdf_png" || targetKey === "pdf_jpg") && docPages === "all")
            return `${stem}_page-*.${ext}`;
        return `${stem}_converted.${ext}`;
    }

    function labelForOption(options: var, key: string): string {
        const found = options.find(o => o.key === key);
        return found ? found.label : key;
    }

    function kindForExt(ext: string): string {
        const lower = (ext ?? "").toLowerCase();
        if (lower === "pdf")
            return "pdf";
        if (root.imageExts.includes(lower))
            return "image";
        if (root.videoExts.includes(lower))
            return "video";
        if (root.audioExts.includes(lower))
            return "audio";
        if (root.officeExts.includes(lower))
            return "office";
        return "";
    }

    function defaultTargetFor(kind: string, ext: string): string {
        const normExt = ext === "jpeg" ? "jpg" : ext;
        if (kind === "image")
            return normExt === "webp" ? "png" : "webp";
        if (kind === "video")
            return "mp4";
        if (kind === "audio")
            return normExt === "mp3" ? "flac" : "mp3";
        if (kind === "pdf")
            return "pdf_compress";
        if (kind === "office")
            return "to_pdf";
        return "";
    }

    function formatBytes(bytes: real): string {
        if (!bytes || bytes <= 0)
            return "0 B";
        const units = ["B", "KB", "MB", "GB"];
        let val = bytes;
        let u = 0;
        while (val >= 1024 && u < units.length - 1) {
            val /= 1024;
            u++;
        }
        return `${val >= 10 || u === 0 ? Math.round(val) : val.toFixed(1)} ${units[u]}`;
    }

    function selectFile(path: string, sizeBytes: real): void {
        const clean = (path ?? "").trim().replace(/^file:\/\//, "");
        if (!clean) {
            clearSelection();
            return;
        }

        const slashIdx = clean.lastIndexOf("/");
        const name = slashIdx >= 0 ? clean.slice(slashIdx + 1) : clean;
        const dir = slashIdx > 0 ? clean.slice(0, slashIdx) : "/";
        const dotIdx = name.lastIndexOf(".");
        const ext = dotIdx > 0 ? name.slice(dotIdx + 1).toLowerCase() : "";
        const kind = kindForExt(ext);

        root.errorText = "";
        root.statusText = "";
        root.lastOutputPath = "";

        if (!kind) {
            root.errorText = Tr.tr("Unsupported file type: .%1").arg(ext || "?");
            return;
        }

        root.selectedPath = clean;
        root.selectedName = name;
        root.selectedDir = dir;
        root.selectedExt = ext;
        root.selectedKind = kind;
        root.selectedSizeBytes = sizeBytes > 0 ? sizeBytes : 0;
        root.selectedSize = sizeBytes > 0 ? formatBytes(sizeBytes) : "";
        root.targetKey = defaultTargetFor(kind, ext);

        if (!root.selectedSize) {
            statProc.targetPath = clean;
            statProc.running = false;
            statProc.running = true;
        }

        toolCheckProc.running = false;
        toolCheckProc.running = true;
        root.revision++;
    }

    function clearSelection(): void {
        root.selectedPath = "";
        root.selectedName = "";
        root.selectedDir = "";
        root.selectedExt = "";
        root.selectedSize = "";
        root.selectedSizeBytes = 0;
        root.selectedKind = "";
        root.targetKey = "";
        root.errorText = "";
        root.statusText = "";
        root.lastOutputPath = "";
        root.revision++;
    }

    function openFileDialog(screenState: var): void {
        root.pendingScreenState = screenState;
        fileDialog.title = Tr.tr("Select a file to convert");
        fileDialog.filterLabel = Tr.tr("Supported files");
        fileDialog.filters = root.allSupportedExts;

        // Close the layer-shell launcher first so the FloatingWindow dialog
        // opens unobstructed on top and takes focus cleanly.
        if (screenState)
            screenState.launcher = false;
        reopenTimer.stop();
        openDialogTimer.restart();
    }

    function scheduleReopenLauncher(): void {
        if (root.pendingScreenState)
            reopenTimer.restart();
    }

    function reopenLauncher(): void {
        const s = root.pendingScreenState;
        if (!s)
            return;
        root.pendingScreenState = null;
        s.launcherSearchRequest = `${GlobalConfig.launcher.actionPrefix}convert `;
        s.launcher = true;
    }

    function shQuote(str: string): string {
        return `'${(str ?? "").replace(/'/g, "'\\''")}'`;
    }

    function cancelConvert(): void {
        if (!root.busy)
            return;
        convertProc.running = false;
        root.busy = false;
        root.statusText = Tr.tr("Conversion cancelled");
    }

    function startConvert(): void {
        if (root.busy || !root.selectedPath || !root.selectedKind || !root.targetKey)
            return;

        root.errorText = "";
        root.statusText = Tr.tr("Converting...");
        root.lastOutputPath = "";
        root.lastOutputName = "";
        root.lastOutputSize = "";

        const inFile = root.selectedPath;
        const dir = root.selectedDir || Paths.home;
        const dotIdx = root.selectedName.lastIndexOf(".");
        const stem = dotIdx > 0 ? root.selectedName.slice(0, dotIdx) : root.selectedName;
        const ext = root.targetExtension;
        const kind = root.selectedKind;
        const target = root.targetKey;

        const baseSuffix = (kind === "pdf" && target === "pdf_compress") ? "_compressed" : "_converted";
        let script = `set -e\nexport PATH="$HOME/.local/bin:$PATH"\nIN=${shQuote(inFile)}\n`;
        script += `if [ ! -f "$IN" ]; then echo "USER_ERR:File not found" >&2; exit 2; fi\n`;
        script += `DIR=${shQuote(dir)}\nSTEM=${shQuote(stem)}\nEXT=${shQuote(ext)}\nSUFFIX=${shQuote(baseSuffix)}\n`;
        script += `OUT="$DIR/\${STEM}\${SUFFIX}.\${EXT}"\nN=2\nwhile [ -e "$OUT" ]; do OUT="$DIR/\${STEM}\${SUFFIX}_\${N}.\${EXT}"; N=$((N+1)); done\n`;

        if (kind === "image") {
            const qObj = root.imageQualities.find(q => q.key === root.imgQuality);
            const qVal = qObj ? qObj.value : 90;
            const stripFlag = root.imgStripExif ? "-strip" : "";
            const rotateFlag = root.imgRotate !== "0" ? `-rotate ${root.imgRotate}` : "";
            const jpgAlphaFlag = ext === "jpg" ? "-background white -alpha remove -alpha off" : "";
            let resizeFlag = "";
            if (root.imgResize === "1920")
                resizeFlag = "-resize '1920x1920>'";
            else if (root.imgResize === "1280")
                resizeFlag = "-resize '1280x1280>'";
            else if (root.imgResize === "75%")
                resizeFlag = "-resize 75%";
            else if (root.imgResize === "50%")
                resizeFlag = "-resize 50%";

            if (ext === "ico") {
                script += `magick "$IN" ${stripFlag} ${rotateFlag} -resize 256x256 "$OUT"\n`;
            } else {
                const losslessFlag = (root.imgQuality === "lossless" && ext === "webp") ? "-define webp:lossless=true" : "";
                const qualityFlag = ext === "png" ? "" : `-quality ${qVal}`;
                script += `magick "$IN" ${stripFlag} ${rotateFlag} ${resizeFlag} ${jpgAlphaFlag} ${losslessFlag} ${qualityFlag} "$OUT"\n`;
            }
        } else if (kind === "video") {
            const qObj = root.videoQualities.find(q => q.key === root.vidQuality);
            const crf = qObj ? qObj.crf : 23;
            const vfParts = [];
            if (root.vidResolution !== "original")
                vfParts.push(`scale=-2:${root.vidResolution}`);
            if (root.vidFps !== "original")
                vfParts.push(`fps=${root.vidFps}`);

            if (ext === "mp3") {
                const afFlag = root.audNormalize ? "-af loudnorm" : "";
                script += `ffmpeg -y -nostdin -i "$IN" -vn ${afFlag} -c:a libmp3lame -b:a ${root.audBitrate} "$OUT"\n`;
            } else if (ext === "wav") {
                const afFlag = root.audNormalize ? "-af loudnorm" : "";
                script += `ffmpeg -y -nostdin -i "$IN" -vn ${afFlag} -c:a pcm_s16le "$OUT"\n`;
            } else if (ext === "gif") {
                const gifScale = root.vidResolution !== "original" ? `scale=-2:${root.vidResolution}:flags=lanczos` : "scale='min(640,iw)':-2:flags=lanczos";
                const gifFps = root.vidFps !== "original" ? `fps=${root.vidFps}` : "fps=15";
                script += `ffmpeg -y -nostdin -i "$IN" -vf "${gifFps},${gifScale},split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$OUT"\n`;
            } else if (ext === "webm") {
                const vfFlag = vfParts.length > 0 ? `-vf "${vfParts.join(",")}"` : "";
                const audioCodec = root.vidMute ? "-an" : "-c:a libopus -b:a 128k";
                script += `ffmpeg -y -nostdin -i "$IN" ${vfFlag} -c:v libvpx-vp9 -crf ${crf} -b:v 0 ${audioCodec} "$OUT"\n`;
            } else {
                const vfFlag = vfParts.length > 0 ? `-vf "${vfParts.join(",")}"` : "";
                const audioCodec = root.vidMute ? "-an" : "-c:a aac -b:a 192k";
                const mp4Flags = ext === "mp4" ? "-movflags +faststart" : "";
                script += `ffmpeg -y -nostdin -i "$IN" ${vfFlag} -c:v libx264 -pix_fmt yuv420p -preset medium -crf ${crf} ${audioCodec} ${mp4Flags} "$OUT"\n`;
            }
        } else if (kind === "audio") {
            const arFlag = root.audSampleRate !== "original" ? `-ar ${root.audSampleRate}` : "";
            const afFlag = root.audNormalize ? `-af loudnorm` : "";
            let codecFlags = "";
            if (ext === "mp3")
                codecFlags = `-c:a libmp3lame -b:a ${root.audBitrate}`;
            else if (ext === "flac")
                codecFlags = `-c:a flac`;
            else if (ext === "wav")
                codecFlags = `-c:a pcm_s16le`;
            else if (ext === "ogg")
                codecFlags = `-c:a libvorbis -b:a ${root.audBitrate}`;
            else if (ext === "m4a")
                codecFlags = `-c:a aac -b:a ${root.audBitrate}`;

            script += `ffmpeg -y -nostdin -i "$IN" -vn ${arFlag} ${afFlag} ${codecFlags} "$OUT"\n`;
        } else if (kind === "pdf") {
            const qObj = root.docQualities.find(q => q.key === root.docQuality) ?? root.docQualities[1];
            if (target === "pdf_compress") {
                script += `gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=${qObj.gs} -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$OUT" "$IN"\n`;
            } else if (target === "pdf_png" || target === "pdf_jpg") {
                const fmtFlag = target === "pdf_png" ? "-png" : "-jpeg";
                if (root.docPages === "first") {
                    const pfx = `\${OUT%.\${EXT}}`;
                    script += `pdftoppm ${fmtFlag} -r ${qObj.dpi} -f 1 -l 1 -singlefile "$IN" "${pfx}"\n`;
                } else {
                    script += `PFX="$DIR/\${STEM}_page"\n`;
                    script += `pdftoppm ${fmtFlag} -r ${qObj.dpi} "$IN" "$PFX"\n`;
                    script += `FIRST=$(ls -1t "$PFX"-*.${ext} 2>/dev/null | tail -n 1 || true)\n`;
                    script += `if [ -n "$FIRST" ]; then OUT="$FIRST"; fi\n`;
                }
            } else if (target === "pdf_txt") {
                script += `pdftotext -layout "$IN" "$OUT"\n`;
            } else if (target === "pdf_docx") {
                script += `if command -v pdf2docx >/dev/null 2>&1; then\n`;
                script += `  pdf2docx convert "$IN" "$OUT" >/dev/null 2>&1\n`;
                script += `elif command -v soffice >/dev/null 2>&1; then\n`;
                script += `  TMPDIR=$(mktemp -d)\n`;
                script += `  soffice -env:UserInstallation="file://$TMPDIR/profile" --headless --infilter="writer_pdf_import" --convert-to docx --outdir "$TMPDIR" "$IN" >/dev/null 2>&1\n`;
                script += `  GEN=$(ls -1 "$TMPDIR"/*.docx 2>/dev/null | head -n 1 || true)\n`;
                script += `  if [ -n "$GEN" ]; then mv "$GEN" "$OUT"; rm -rf "$TMPDIR"; else rm -rf "$TMPDIR"; echo "USER_ERR:LibreOffice failed to convert PDF to DOCX" >&2; exit 1; fi\n`;
                script += `else\n`;
                script += `  echo "USER_ERR:Install pdf2docx (uv tool install pdf2docx) or LibreOffice for PDF → DOCX" >&2\n`;
                script += `  exit 2\n`;
                script += `fi\n`;
            }
        } else if (kind === "office") {
            const targetFmt = root.targetExtension;
            script += `if command -v soffice >/dev/null 2>&1; then\n`;
            script += `  TMPDIR=$(mktemp -d)\n`;
            script += `  soffice -env:UserInstallation="file://$TMPDIR/profile" --headless --convert-to ${targetFmt} --outdir "$TMPDIR" "$IN" >/dev/null 2>&1\n`;
            script += `  GEN=$(ls -1 "$TMPDIR"/*.${targetFmt} 2>/dev/null | head -n 1 || true)\n`;
            script += `  if [ -n "$GEN" ]; then mv "$GEN" "$OUT"; rm -rf "$TMPDIR"; else rm -rf "$TMPDIR"; echo "USER_ERR:LibreOffice failed to convert to .${targetFmt}" >&2; exit 1; fi\n`;
            script += `elif command -v pandoc >/dev/null 2>&1; then\n`;
            script += `  pandoc "$IN" -o "$OUT"\n`;
            script += `else\n`;
            script += `  echo "USER_ERR:Install LibreOffice (sudo pacman -S libreoffice-fresh) to convert Office documents" >&2\n`;
            script += `  exit 2\n`;
            script += `fi\n`;
        }

        script += `SIZE=$(stat -c '%s' "$OUT" 2>/dev/null || echo 0)\n`;
        script += `printf 'RESULT\\t%s\\t%s\\n' "$SIZE" "$OUT"\n`;

        root.busy = true;
        convertProc.command = ["bash", "-c", script];
        convertProc.running = false;
        convertProc.running = true;
    }

    Component.onCompleted: toolCheckProc.running = true

    Process {
        id: toolCheckProc

        command: ["bash", "-c", "export PATH=\"$HOME/.local/bin:$PATH\"; command -v pdftotext >/dev/null 2>&1 && echo PDFTOTEXT; command -v soffice >/dev/null 2>&1 && echo SOFFICE; command -v pandoc >/dev/null 2>&1 && echo PANDOC; command -v pdf2docx >/dev/null 2>&1 && echo PDF2DOCX; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hasPdftotext = text.includes("PDFTOTEXT");
                root.hasSoffice = text.includes("SOFFICE");
                root.hasPandoc = text.includes("PANDOC");
                root.hasPdf2docx = text.includes("PDF2DOCX");
            }
        }
    }

    Timer {
        id: openDialogTimer

        interval: 40
        onTriggered: fileDialog.open()
    }

    Timer {
        id: reopenTimer

        interval: 80
        onTriggered: root.reopenLauncher()
    }

    FileDialog {
        id: fileDialog

        title: Tr.tr("Select a file to convert")
        onAccepted: path => {
            root.selectFile(path, 0);
            root.scheduleReopenLauncher();
        }
        onRejected: root.scheduleReopenLauncher()
    }

    Process {
        id: statProc

        property string targetPath: ""

        command: ["stat", "-c", "%s", targetPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const bytes = parseFloat(text.trim()) || 0;
                if (bytes > 0 && root.selectedPath === statProc.targetPath) {
                    root.selectedSizeBytes = bytes;
                    root.selectedSize = root.formatBytes(bytes);
                    root.revision++;
                }
            }
        }
    }

    Process {
        id: convertProc

        property string lastStdout: ""
        property string lastStderr: ""

        stdout: StdioCollector {
            onStreamFinished: convertProc.lastStdout = text
        }
        stderr: StdioCollector {
            onStreamFinished: convertProc.lastStderr = text
        }
        onStarted: {
            lastStdout = "";
            lastStderr = "";
        }
        onExited: code => {
            root.busy = false;
            if (code === 0) {
                const lines = convertProc.lastStdout.trim().split("\n");
                let outPath = "";
                let outSize = 0;
                for (let i = lines.length - 1; i >= 0; i--) {
                    if (lines[i].startsWith("RESULT\t")) {
                        const parts = lines[i].split("\t");
                        outSize = parseFloat(parts[1]) || 0;
                        outPath = parts.slice(2).join("\t");
                        break;
                    }
                }
                if (outPath) {
                    const slashIdx = outPath.lastIndexOf("/");
                    root.lastOutputPath = outPath;
                    root.lastOutputName = slashIdx >= 0 ? outPath.slice(slashIdx + 1) : outPath;
                    root.lastOutputSize = root.formatBytes(outSize);

                    let sizeSummary = root.lastOutputSize;
                    if (root.selectedSizeBytes > 0 && outSize > 0) {
                        const diffPct = Math.round(((outSize - root.selectedSizeBytes) / root.selectedSizeBytes) * 100);
                        const sign = diffPct > 0 ? `+${diffPct}%` : `${diffPct}%`;
                        sizeSummary = `${root.selectedSize} → ${root.lastOutputSize} (${sign})`;
                    }

                    root.statusText = Tr.tr("Saved %1 · %2").arg(root.lastOutputName).arg(sizeSummary);
                    Quickshell.execDetached(["notify-send", "-a", "Caelestia Converter", "-i", "document-save", Tr.tr("Conversion complete"), `${root.lastOutputName}\n${sizeSummary}`]);
                } else {
                    root.statusText = Tr.tr("Conversion complete");
                }
            } else {
                const err = convertProc.lastStderr.trim();
                const userErrIdx = err.indexOf("USER_ERR:");
                if (userErrIdx >= 0) {
                    root.errorText = err.slice(userErrIdx + "USER_ERR:".length).split("\n")[0];
                } else {
                    const errLines = err.split("\n").filter(l => l.trim().length > 0);
                    root.errorText = errLines.length > 0 ? errLines[errLines.length - 1] : Tr.tr("Conversion failed (exit code %1)").arg(code);
                }
                root.statusText = "";
            }
            root.revision++;
        }
    }
}
