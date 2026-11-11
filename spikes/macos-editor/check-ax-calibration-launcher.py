#!/usr/bin/env python3
"""Check launcher refusal/dispatch using fake processes; never build or launch."""

from contextlib import ExitStack, nullcontext, redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).resolve().with_name("run-ax-calibration.py")


class CalibrationLauncherChecks(unittest.TestCase):
    def setUp(self):
        self.g = {"__file__": str(SCRIPT), "__name__": "calibration_launcher_checks"}
        exec(compile(SCRIPT.read_text(), str(SCRIPT), "exec"), self.g)

    def test_invalid_or_help_cli_never_reaches_admission(self):
        for args, code in [([], 2), (["--help"], 0), (["--run-visible"], 2),
                           (["--build-only", "--foreground-coordinated"], 2),
                           (["--build-only", "--run-visible", "--foreground-coordinated"], 2)]:
            with self.subTest(args=args):
                gate = Mock(side_effect=AssertionError("Unexpected admission"))
                with patch.dict(self.g, admission=gate), patch("sys.argv", [str(SCRIPT), *args]), \
                        redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as result:
                        self.g["main"]()
                    self.assertEqual(result.exception.code, code)
                gate.assert_not_called()

    def test_build_and_launch_dispatch_are_separate(self):
        for args, counts in [(["--build-only"], (1, 0)),
                             (["--run-visible", "--foreground-coordinated"], (0, 1))]:
            with self.subTest(args=args):
                build, launch = Mock(), Mock()
                with patch.dict(self.g, admission=Mock(), owner=Mock(), operation_lock=nullcontext,
                                build=build, run_visible=launch), patch("sys.argv", [str(SCRIPT), *args]):
                    self.g["main"]()
                self.assertEqual((build.call_count, launch.call_count), counts)

    def test_admission_fails_closed_without_starting_work(self):
        g = self.g
        with ExitStack() as stack:
            stack.enter_context(patch("sys.platform", "darwin"))
            stack.enter_context(patch.object(g["platform"], "machine", return_value="arm64"))
            disk = stack.enter_context(patch.object(g["shutil"], "disk_usage", return_value=SimpleNamespace(free=40*1024**3)))
            load = stack.enter_context(patch.object(g["os"], "getloadavg", return_value=(1, 1, 1)))
            ps = stack.enter_context(patch.object(g["subprocess"], "run", return_value=SimpleNamespace(stdout="123 /usr/bin/python3\n")))
            g["admission"]()
            for low_disk, high_load in [(True, False), (False, True)]:
                disk.return_value.free = (19 if low_disk else 40)*1024**3
                load.return_value = (32 if high_load else 1, 1, 1)
                before = ps.call_count
                with self.assertRaises(RuntimeError):
                    g["admission"]()
                self.assertEqual(ps.call_count, before)
            disk.return_value.free, load.return_value = 40*1024**3, (1, 1, 1)
            for row in ["321 /usr/bin/xcodebuild\n", "322 /usr/bin/swift-frontend\n",
                        "323 /tmp/NativeCollectionChecks\n", "324 /tmp/MarkrightAXCalibration\n",
                        "325 /tmp/ExampleUITests-Runner\n", "malformed\n", ""]:
                with self.subTest(row=row):
                    ps.return_value = SimpleNamespace(stdout=row)
                    with self.assertRaises(RuntimeError):
                        g["admission"]()
            ps.side_effect = subprocess.CalledProcessError(1, "mock ps")
            with self.assertRaises(subprocess.SubprocessError):
                g["admission"]()

    def test_owned_paths_and_operation_lock_refuse_unknown_outputs(self):
        g = self.g
        with tempfile.TemporaryDirectory(prefix="mrk-ax-launcher-check-") as temporary:
            # macOS's /var alias is itself a symlink; test the real temp root.
            root = Path(temporary).resolve()
            with patch.dict(g, BUILD=root/"owned"):
                g["owner"](create=True)
                g["owner"]()
                self.assertEqual(g["read_json"](g["BUILD"]/".markright-owned-calibration.json"), g["OWNER"])
                with g["operation_lock"]():
                    with self.assertRaises(RuntimeError):
                        with g["operation_lock"]():
                            self.fail("Overlapping lock acquired")
                self.assertFalse((g["BUILD"]/".operation.lock").exists())
            unknown = root/"unknown"
            unknown.mkdir()
            (unknown/"keep").write_text("unique")
            with patch.dict(g, BUILD=unknown), self.assertRaises(RuntimeError):
                g["owner"](create=True)
            self.assertEqual([p.name for p in unknown.iterdir()], ["keep"])
            linked = root/"linked"
            linked.symlink_to(unknown, target_is_directory=True)
            with patch.dict(g, BUILD=linked), self.assertRaises(RuntimeError):
                g["owner"](create=True)
            for invalid in ["../escape", "/tmp/escape", None, "x"]:
                with self.subTest(build_id=invalid), self.assertRaises(RuntimeError):
                    g["app_paths"](invalid)

    def test_stale_launch_refuses_and_matching_launch_only_dispatches_synthetic_flag(self):
        g = self.g
        with tempfile.TemporaryDirectory(prefix="mrk-ax-launcher-check-") as temporary:
            root = Path(temporary).resolve()
            source = root/"Source.swift"
            source.write_text("synthetic")
            with patch.dict(g, ROOT=root, BUILD=root, SOURCES=[source], admission=Mock()):
                build_id = "20261111T000000Z-" + "a"*32
                folder, contents, executable = g["app_paths"](build_id)
                executable.parent.mkdir(parents=True)
                executable.write_bytes(b"fake non-executed binary")
                info = contents/"Info.plist"
                info.write_bytes(plistlib.dumps(g["PLIST"]))
                g["write_json"](root/"current.json", {"build_id": build_id})
                metadata = {"owner": g["OWNER"], "build_id": build_id, "source_sha256": g["inputs"](),
                            "launcher_sha256": g["launcher_hash"](), "architecture": g["platform"].machine(),
                            "minimum_macos": "14.0", "binary_sha256": g["digest"](executable, g["MAXIMUM_BINARY"])}
                metadata_path = folder/"build.json"
                with patch.object(g["subprocess"], "Popen", side_effect=AssertionError("Unexpected launch")):
                    for key, value in [("owner", {}), ("source_sha256", {}), ("launcher_sha256", "stale"),
                                       ("architecture", "wrong"), ("minimum_macos", "99"), ("binary_sha256", "wrong")]:
                        with self.subTest(mismatch=key):
                            metadata_path.write_text(json.dumps({**metadata, key: value}))
                            with self.assertRaises(RuntimeError):
                                g["run_visible"]()
                    metadata_path.write_text(json.dumps(metadata))
                    info.write_bytes(plistlib.dumps({**g["PLIST"], "LSUIElement": True}))
                    with self.assertRaises(RuntimeError):
                        g["run_visible"]()
                info.write_bytes(plistlib.dumps(g["PLIST"]))
                with patch.object(g["subprocess"], "Popen", return_value=SimpleNamespace(pid=999)) as popen, \
                        patch.dict(g["os"].environ, MARKRIGHT_PREVIEW_SNAPSHOTS="unrequested"), redirect_stdout(io.StringIO()):
                    g["run_visible"]()
                    self.assertEqual(popen.call_args.args[0], [str(executable), "--show-synthetic-window"])
                    self.assertNotIn("MARKRIGHT_PREVIEW_SNAPSHOTS", popen.call_args.kwargs["env"])
                    self.assertEqual(len(list(folder.glob("runtime-*.log"))), 1)

    def test_mock_build_selects_only_unchanged_inputs_without_launch(self):
        g = self.g
        with tempfile.TemporaryDirectory(prefix="mrk-ax-launcher-check-") as temporary:
            root = Path(temporary).resolve()
            source = root/"Source.swift"
            source.write_text("synthetic")
            cache = root/"cache"
            cache.mkdir()
            def fake_compile(command, log):
                Path(command[-1]).write_bytes(b"fake compile output")
                log.write_text("Mock compiler only; no native tool executed.\n")
            def changing_compile(command, log):
                fake_compile(command, log)
                source.write_text("changed during mock compile")
            for compiler, should_select in [(fake_compile, True), (changing_compile, False)]:
                output = root/("good" if should_select else "changed")
                output.mkdir()
                with patch.dict(g, ROOT=root, BUILD=output, CACHE=cache, SOURCES=[source],
                                admission=Mock(), compile_owned=compiler), \
                        patch.object(g["subprocess"], "run", return_value=SimpleNamespace(stdout="abc123\n")), \
                        patch.object(g["subprocess"], "Popen", side_effect=AssertionError("Unexpected process")), \
                        redirect_stdout(io.StringIO()):
                    if should_select:
                        g["build"]()
                        current = g["read_json"](output/"current.json")
                        folder, _, _ = g["app_paths"](current["build_id"])
                        self.assertEqual(g["read_json"](folder/"build.json")["source_sha256"], g["inputs"]())
                    else:
                        with self.assertRaises(RuntimeError):
                            g["build"]()
                        self.assertFalse((output/"current.json").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
