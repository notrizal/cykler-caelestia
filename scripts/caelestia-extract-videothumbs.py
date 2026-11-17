#!/usr/bin/env python3
"""Extracts cached 720p JPEG thumbnails for video wallpapers.

Matches the djb2 path hash used by services/Wallpapers.qml so the shell's
wallpaper pickers can load static JPEG previews instead of opening QMediaPlayer
instances per item. Prints each newly extracted video's resolved path to stdout
as it completes.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import subprocess
import sys
import threading

VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov", ".avi"}


def djb2_hash(value: str) -> str:
    """Compute the unsigned 32-bit DJB2 hash matching QML's djb2Hash()."""
    h = 5381
    for ch in value:
        h = (((h << 5) + h) + ord(ch)) & 0xFFFFFFFF
    return str(h)


def default_cache_dir() -> Path:
    xdg_cache = os.environ.get("XDG_CACHE_HOME")
    base = Path(xdg_cache) if xdg_cache else Path.home() / ".cache"
    return base / "caelestia" / "videothumbs"


def probe_seek_time(video_path: Path) -> float:
    """Pick a representative frame at 30% of the clip duration."""
    try:
        out = subprocess.check_output(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "csv=p=0",
                str(video_path),
            ],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).strip()
        duration = float(out) if out else 0.0
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0.1

    if duration > 0.3:
        return max(0.1, min(duration * 0.3, duration - 0.1))
    return 0.1


def extract_thumbnail(video_path: Path, output_path: Path) -> bool:
    """Extract one scaled JPEG frame atomically using ffmpeg."""
    tmp_path = output_path.with_name(f".{output_path.name}.{threading.get_ident()}.tmp")
    seek = probe_seek_time(video_path)

    for ss in (f"{seek:.2f}", "0"):
        try:
            subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-loglevel",
                    "error",
                    "-ss",
                    ss,
                    "-i",
                    str(video_path),
                    "-vframes",
                    "1",
                    "-vf",
                    "scale=-1:720",
                    "-q:v",
                    "2",
                    "-f",
                    "image2",
                    str(tmp_path),
                ],
                check=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=20,
            )
            if tmp_path.is_file() and tmp_path.stat().st_size > 0:
                os.replace(tmp_path, output_path)
                return True
        except (OSError, subprocess.SubprocessError):
            pass
        finally:
            if tmp_path.exists():
                try:
                    tmp_path.unlink()
                except OSError:
                    pass

    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract video wallpaper thumbnails")
    parser.add_argument("--dir", type=Path, default=Path.home() / "Pictures" / "Wallpapers", help="Wallpapers root directory")
    parser.add_argument("--cache-dir", type=Path, default=default_cache_dir(), help="Output thumbnail cache directory")
    parser.add_argument("--force", action="store_true", help="Regenerate thumbnails even when up to date")
    args = parser.parse_args()

    walls_dir = args.dir.expanduser()
    if not walls_dir.is_dir():
        return 0

    cache_dir = args.cache_dir.expanduser()
    cache_dir.mkdir(parents=True, exist_ok=True)

    videos: list[Path] = []
    for root, _, files in os.walk(walls_dir):
        for name in files:
            p = Path(root) / name
            if p.suffix.lower() in VIDEO_EXTENSIONS and p.is_file():
                videos.append(p)

    if not videos:
        return 0

    stdout_lock = threading.Lock()

    def process(video: Path) -> None:
        try:
            abs_path = Path(os.path.abspath(video))
            thumb = cache_dir / f"{djb2_hash(str(abs_path))}.jpg"

            if not args.force and thumb.is_file():
                try:
                    if thumb.stat().st_size > 0 and thumb.stat().st_mtime >= abs_path.stat().st_mtime:
                        return
                except OSError:
                    pass

            if extract_thumbnail(abs_path, thumb):
                with stdout_lock:
                    print(str(abs_path), flush=True)
        except OSError as exc:
            print(f"caelestia-extract-videothumbs: {exc}", file=sys.stderr)

    workers = min(8, max(2, os.cpu_count() or 4))
    with ThreadPoolExecutor(max_workers=workers) as executor:
        for _ in executor.map(process, videos):
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
