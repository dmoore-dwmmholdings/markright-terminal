#!/usr/bin/env python3
"""Build and run the separate, invisible AppKit collection checks on macOS."""

from pathlib import Path
import os
import platform
import plistlib
import shutil
import subprocess
import sys


DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parent.parent
BUILD = ROOT / "spikes" / ".build" / "macos-native-collection-checks"
MINIMUM_FREE = 20 * 1024**3
TIMEOUT_SECONDS = 90


def require_headroom():
    if shutil.disk_usage(ROOT).free < MINIMUM_FREE:
        raise RuntimeError("Below 20 GiB free; no further compile or probe process started.")


def main():
    if sys.platform != "darwin":
        raise RuntimeError("The native collection checks require macOS and the Xcode command line tools.")
    require_headroom()
    contents = BUILD / "NativeCollectionChecks.app" / "Contents"
    executable = contents / "MacOS" / "NativeCollectionChecks"
    cache = BUILD / "ModuleCache"
    executable.parent.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({
            "CFBundleIdentifier": "com.dwmm.markright.spike.native-collection-checks",
            "CFBundleExecutable": "NativeCollectionChecks",
            "CFBundlePackageType": "APPL",
            "LSUIElement": True,
        }, stream)
    shared = DIRECTORY.parent / "ios-editor" / "Sources"
    sources = [shared / name for name in (
        "CollectionStore.swift", "RecoveryDraft.swift", "DocumentSession.swift",
        "SourceSelection.swift", "EditorModel.swift",
    )] + [
        DIRECTORY / "Sources" / "MacSourceEditor.swift",
        DIRECTORY / "Sources" / "MacCollectionWorkspace.swift",
        DIRECTORY / "NativeCollectionChecks" / "main.swift",
    ]
    require_headroom()
    subprocess.run([
        "/usr/bin/xcrun", "swiftc", "-swift-version", "6", "-warnings-as-errors",
        "-parse-as-library", "-target", f"{platform.machine()}-apple-macos14.0",
        "-module-cache-path", str(cache), *map(str, sources), "-o", str(executable),
    ], cwd=ROOT, check=True, timeout=TIMEOUT_SECONDS)
    if executable.stat().st_size > 20 * 1024**2:
        raise RuntimeError("Unexpectedly large probe executable; not launched.")
    require_headroom()
    # Run this private executable directly; never open/activate the research app.
    environment = dict(os.environ)
    environment["NSUnbufferedIO"] = "YES"
    subprocess.run([str(executable)], cwd=ROOT, env=environment, check=True, timeout=TIMEOUT_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
