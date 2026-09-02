import importlib.util
from pathlib import Path
import unittest


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


if __name__ == "__main__":
    unittest.main()
