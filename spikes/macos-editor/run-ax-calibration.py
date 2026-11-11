#!/usr/bin/env python3
"""Build OR explicitly launch an owned, synthetic visible AX calibration app."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import uuid


DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parent.parent
BUILD = ROOT / "spikes" / ".build" / "macos-ax-calibration"
CACHE = ROOT / "spikes" / ".build" / "macos-native-collection-checks" / "ModuleCache"
OWNER = {"kind": "markright-synthetic-ax-calibration", "version": 1}
EXECUTABLE_NAME = "MarkrightAXCalibration"
PLIST = {
    "CFBundleIdentifier": "com.dwmm.markright.spike.ax-calibration",
    "CFBundleExecutable": EXECUTABLE_NAME,
    "CFBundleDisplayName": "Markright AX Calibration",
    "CFBundleName": "Markright AX Calibration",
    "CFBundlePackageType": "APPL",
    "LSMinimumSystemVersion": "14.0",
    "LSUIElement": False,
}
SHARED = ROOT / "spikes" / "ios-editor" / "Sources"
SOURCES = [SHARED / name for name in (
    "EditorModel.swift", "SourceSelection.swift", "MarkdownInsertion.swift",
    "MarkdownTableInsertion.swift", "SourcePreviewProjection.swift", "SourcePreviewPanel.swift",
)] + [DIRECTORY / "Sources" / "MacSourceEditor.swift", DIRECTORY / "AXCalibration" / "main.swift"]
BUSY_NAMES = {
    "swift", "swift-test", "swiftc", "swift-frontend", "xcodebuild", "xcodegen",
    "clang", "clang++", "xctest", "NativeCollectionChecks", EXECUTABLE_NAME,
}
MINIMUM_FREE = 20 * 1024**3
MAXIMUM_BINARY = 20 * 1024**2


def checked_path(path, *, directory=False, absent=False):
    """Refuse symlink components, including an already-existing output leaf."""
    for component in [*reversed(path.parents), path]:
        if component.is_symlink():
            raise RuntimeError(f"Symlink path refused: {component}")
    if path.exists():
        mode = path.stat().st_mode
        if absent or not (stat.S_ISDIR(mode) if directory else stat.S_ISREG(mode)):
            raise RuntimeError(f"Unexpected existing path: {path}")
    elif not absent:
        raise RuntimeError(f"Required path missing: {path}")
    return path


def digest(path, limit):
    checked_path(path)
    if path.stat().st_size > limit:
        raise RuntimeError(f"Unexpectedly large input: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    checked_path(path)
    if path.stat().st_size > 64 * 1024:
        raise RuntimeError("Unexpectedly large calibration metadata.")
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    checked_path(path, absent=True)
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def admission():
    if sys.platform != "darwin" or platform.machine() not in {"arm64", "x86_64"}:
        raise RuntimeError("Requires a supported Mac and existing Xcode command line tools.")
    if shutil.disk_usage(ROOT).free < MINIMUM_FREE or os.getloadavg()[0] >= 32:
        raise RuntimeError("Admission refused: require 20 GiB free and one-minute load below 32.")
    # Fail closed if the process inventory cannot be read. This does not acquire
    # a host-wide reservation; peer coordination remains a separate requirement.
    result = subprocess.run(["/bin/ps", "-A", "-o", "pid=,comm="],
                            capture_output=True, text=True, check=True, timeout=10)
    rows = [row.strip().split(None, 1) for row in result.stdout.splitlines() if row.strip()]
    if not rows or any(len(row) != 2 or not row[0].isdigit() for row in rows):
        raise RuntimeError("Admission refused: incomplete process inventory.")
    busy = [(pid, Path(command).name) for pid, command in rows
            if Path(command).name in BUSY_NAMES or ".xctest" in command
            or Path(command).name.endswith("UITests-Runner")]
    if busy:
        raise RuntimeError("Admission refused: native/compiler jobs remain: " +
                           ", ".join(f"{pid}:{name}" for pid, name in busy))


def owner(*, create=False):
    marker = BUILD / ".markright-owned-calibration.json"
    if BUILD.exists() or BUILD.is_symlink():
        checked_path(BUILD, directory=True)
        if read_json(marker) != OWNER:
            raise RuntimeError("Unknown calibration output owner; refusing to reuse.")
    elif create:
        checked_path(BUILD, absent=True)
        BUILD.mkdir(parents=True, exist_ok=False)
        write_json(marker, OWNER)
    else:
        raise RuntimeError("No owned calibration build. Use --build-only in a coordinated slot first.")


@contextmanager
def operation_lock():
    path = BUILD / ".operation.lock"
    checked_path(path, absent=True)
    with path.open("x", encoding="utf-8") as stream:
        stream.write(str(os.getpid()) + "\n")
    try:
        yield
    finally:
        path.unlink()


def inputs():
    return {str(path.relative_to(ROOT)): digest(path, 2 * 1024**2) for path in SOURCES}


def launcher_hash():
    return digest(Path(__file__).resolve(), 256 * 1024)


def new_id():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex


def app_paths(build_id):
    if not isinstance(build_id, str) or not re.fullmatch(r"\d{8}T\d{6}Z-[a-f0-9]{32}", build_id):
        raise RuntimeError("Invalid calibration build identifier.")
    folder = BUILD / build_id
    contents = folder / (EXECUTABLE_NAME + ".app") / "Contents"
    return folder, contents, contents / "MacOS" / EXECUTABLE_NAME


def compile_owned(command, log):
    # A timeout cancels only the process group created by this invocation.
    with log.open("xb") as output:
        process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            result = process.wait(timeout=90)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            raise
    if result:
        raise RuntimeError(f"Compile failed ({result}); retained log: {log}")


def build():
    before = inputs()
    helper = launcher_hash()
    # Reuse the established owned native-check cache; do not initialize an
    # unknown cache or download dependencies as part of this diagnostic.
    checked_path(CACHE, directory=True)
    build_id = new_id()
    folder, contents, executable = app_paths(build_id)
    checked_path(folder, absent=True)
    executable.parent.mkdir(parents=True, exist_ok=False)
    with (contents / "Info.plist").open("xb") as stream:
        plistlib.dump(PLIST, stream)
    log = folder / "compile.log"
    admission()
    compile_owned([
        "/usr/bin/xcrun", "swiftc", "-j", "2", "-swift-version", "6", "-warnings-as-errors",
        "-parse-as-library", "-target", f"{platform.machine()}-apple-macos14.0",
        "-module-cache-path", str(CACHE), *map(str, SOURCES), "-o", str(executable),
    ], log)
    if before != inputs() or helper != launcher_hash():
        raise RuntimeError("Inputs changed during compilation; output retained but not selected for launch.")
    revision = subprocess.run(["/usr/bin/git", "rev-parse", "HEAD"], cwd=ROOT,
                              capture_output=True, text=True, check=True, timeout=10).stdout.strip()
    metadata = {
        "owner": OWNER, "build_id": build_id, "git_head": revision,
        "source_sha256": before, "launcher_sha256": helper,
        "binary_sha256": digest(executable, MAXIMUM_BINARY),
        "architecture": platform.machine(), "minimum_macos": "14.0",
    }
    write_json(folder / "build.json", metadata)
    pointer = BUILD / "current.json"
    if pointer.exists() or pointer.is_symlink():
        checked_path(pointer)
    temporary = BUILD / (".current-" + uuid.uuid4().hex + ".json")
    write_json(temporary, {"build_id": build_id})
    os.replace(temporary, pointer)
    print(f"Built only; no app launched. Compile log: {log}")


def run_visible():
    pointer = read_json(BUILD / "current.json")
    folder, contents, executable = app_paths(pointer["build_id"])
    metadata = read_json(folder / "build.json")
    if (metadata.get("owner") != OWNER or metadata.get("build_id") != pointer["build_id"]
            or metadata.get("source_sha256") != inputs()
            or metadata.get("launcher_sha256") != launcher_hash()
            or metadata.get("architecture") != platform.machine()
            or metadata.get("minimum_macos") != "14.0"
            or metadata.get("binary_sha256") != digest(executable, MAXIMUM_BINARY)):
        raise RuntimeError("Stale or mismatched calibration build; not launched.")
    info = checked_path(contents / "Info.plist")
    if info.stat().st_size > 16 * 1024 or plistlib.loads(info.read_bytes()) != PLIST:
        raise RuntimeError("Unexpected app metadata; not launched.")
    environment = dict(os.environ)
    environment["NSUnbufferedIO"] = "YES"
    environment.pop("MARKRIGHT_PREVIEW_SNAPSHOTS", None)
    log = folder / ("runtime-" + new_id() + ".log")
    admission()
    with log.open("xb") as output:
        process = subprocess.Popen([str(executable), "--show-synthetic-window"], cwd=ROOT,
                                   env=environment, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
    print(f"Launched owned PID {process.pid}; runtime log: {log}")
    print("Verify the window and AX metadata with the coordinated observer; launch is not a pass.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--build-only", action="store_true", help="Compile only; never open a window.")
    modes.add_argument("--run-visible", action="store_true", help="Launch an existing matching owned build; never compile.")
    parser.add_argument("--foreground-coordinated", action="store_true",
                        help="Acknowledge an externally coordinated foreground observation slot.")
    arguments = parser.parse_args()
    if arguments.run_visible != arguments.foreground_coordinated:
        parser.error("--run-visible requires --foreground-coordinated, which is valid only with --run-visible")
    admission()
    owner(create=arguments.build_only)
    with operation_lock():
        build() if arguments.build_only else run_visible()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
