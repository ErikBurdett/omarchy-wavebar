import importlib.util
from pathlib import Path
import signal
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "waveform.py"
SPEC = importlib.util.spec_from_file_location("media_waveform", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WaveformFrameTests(unittest.TestCase):
    def test_silence_stays_silent(self) -> None:
        self.assertEqual(MODULE.waveform_frame([0] * 32, 4, [0.0] * 4), [0.0] * 4)

    def test_peak_is_normalized(self) -> None:
        frame = MODULE.waveform_frame([0, 32767, 0, -32768], 2, [0.0] * 2)
        self.assertTrue(all(0.0 <= value <= 1.0 for value in frame))
        self.assertGreater(frame[0], 0.9)
        self.assertEqual(frame[1], 1.0)

    def test_previous_frame_decays(self) -> None:
        frame = MODULE.waveform_frame([], 3, [1.0, 0.5, 0.25])
        self.assertEqual(frame, [0.72, 0.36, 0.18])


class SafetyTests(unittest.TestCase):
    def test_execution_paths_are_absolute(self) -> None:
        self.assertEqual(MODULE.PYTHON_PATH, "/usr/bin/python3")
        self.assertEqual(MODULE.PW_RECORD_PATH, "/usr/bin/pw-record")
        self.assertEqual(MODULE.SETPRIV_PATH, "/usr/bin/setpriv")

    def test_trusted_executable_rejects_writable_system_target(self) -> None:
        directory = mock.Mock(st_uid=0, st_mode=0o40755)
        link = mock.Mock(st_uid=0)
        target = mock.Mock(st_uid=0, st_mode=0o100775)
        with (
            mock.patch.object(MODULE.os, "lstat", return_value=link),
            mock.patch.object(MODULE.os.path, "realpath", return_value="/usr/bin/python3.14"),
            mock.patch.object(MODULE.os, "stat", side_effect=[directory, target]),
        ):
            with self.assertRaises(RuntimeError):
                MODULE.trusted_executable("/usr/bin/python3")

    def test_target_has_byte_and_control_character_limits(self) -> None:
        self.assertEqual(MODULE.checked_target("safe-node"), "safe-node")
        with self.assertRaises(ValueError):
            MODULE.checked_target("x" * 257)
        with self.assertRaises(ValueError):
            MODULE.checked_target("é" * 129)
        with self.assertRaises(ValueError):
            MODULE.checked_target("unsafe\nnode")

    def test_recorder_group_escalates_and_is_reaped(self) -> None:
        process = mock.Mock()
        process.pid = 1234
        process.poll.return_value = None
        process.wait.side_effect = [MODULE.subprocess.TimeoutExpired("pw-record", 1), -9]
        with mock.patch.object(MODULE.os, "killpg") as killpg:
            self.assertEqual(MODULE.reap_process_group(process), -9)
        self.assertEqual(
            killpg.call_args_list,
            [mock.call(1234, signal.SIGTERM), mock.call(1234, signal.SIGKILL)],
        )
        self.assertEqual(process.wait.call_count, 2)

    def test_recorder_environment_does_not_inherit_user_path(self) -> None:
        runtime = mock.Mock(st_uid=1000, st_mode=0o40700)
        with (
            mock.patch.object(MODULE.os, "getuid", return_value=1000),
            mock.patch.object(MODULE.os, "stat", return_value=runtime),
        ):
            environment = MODULE.recorder_environment()
        self.assertEqual(environment["PATH"], "/usr/bin")
        self.assertEqual(environment["XDG_RUNTIME_DIR"], "/run/user/1000")
        self.assertEqual(set(environment), {"LANG", "LC_ALL", "PATH", "XDG_RUNTIME_DIR"})


if __name__ == "__main__":
    unittest.main()
