import os
import sys
import numpy as np
import pytest

# Ensure repository modules can be imported when running pytest directly
REPO_ROOT = os.path.dirname(os.path.dirname(__file__))
SCRIPTS_DIR = os.path.join(REPO_ROOT, "EarprintGUI", "Scripts")
sys.path.insert(0, SCRIPTS_DIR)
sys.path.append(REPO_ROOT)

from impulse_response_estimator import ImpulseResponseEstimator
from constants import SPEAKER_LAYOUTS
from utils import write_wav


def _write_dummy_recordings(out_dir, layout):
    fs = 8000
    ire = ImpulseResponseEstimator(min_duration=0.1, fs=fs)
    test_signal_path = out_dir / "test.wav"
    write_wav(test_signal_path, ire.fs, ire.test_signal)

    silence = np.zeros(int(fs * 2.0))
    column = np.concatenate([silence, ire.test_signal])
    for group in SPEAKER_LAYOUTS[layout]:
        samples = len(column) * len(group)
        data = np.zeros((samples, 2), dtype=np.float32)
        for i in range(len(group)):
            start = i * len(column)
            data[start : start + len(column), 0] = column
            data[start : start + len(column), 1] = column
        write_wav(out_dir / ("%s.wav" % ",".join(group)), fs, data.T)
    return str(out_dir), str(test_signal_path)


@pytest.fixture
def dummy_capture(tmp_path):
    def factory(layout):
        real_dir = os.environ.get("IMPULCIFER_TEST_CAPTURE_DIR")
        if real_dir and os.path.isdir(real_dir):
            return real_dir, None
        out_dir = tmp_path / "capture"
        out_dir.mkdir(exist_ok=True)
        return _write_dummy_recordings(out_dir, layout)

    return factory