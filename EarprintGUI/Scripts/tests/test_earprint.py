import os
import sys
import numpy as np
import pytest

# Allow importing modules from repository root
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

import earprint
from hrir import HRIR
from impulse_response_estimator import ImpulseResponseEstimator
from utils import write_wav

SPEAKERS_916 = [
    "FL",
    "FR",
    "FC",
    "SL",
    "SR",
    "BL",
    "BR",
    "WL",
    "WR",
    "TFL",
    "TFR",
    "TSL",
    "TSR",
    "TBL",
    "TBR",
]


def test_earprint_916_pipeline(tmp_path, dummy_capture, monkeypatch):
    dir_path, test_signal = dummy_capture("9.1.6")
    monkeypatch.setattr("earprint.diffuse_field_compensation", lambda *a, **k: None)
    monkeypatch.setattr("earprint.write_readme", lambda *a, **k: "")
    monkeypatch.setattr("earprint.equalization", lambda *a, **k: (None, None))
    monkeypatch.setattr("hrir.HRIR.crop_heads", lambda self, head_ms=1: None)
    monkeypatch.setattr("hrir.HRIR.correct_channel_balance", lambda self, method=None: None)
    called = {}

    def fake_main(**kwargs):
        called.update(kwargs)
        write_wav(os.path.join(kwargs["dir_path"], "responses.wav"), 8000, np.zeros((1, 2)))

    monkeypatch.setattr(earprint, "main", fake_main)
    earprint.main(
        dir_path=dir_path,
        plot=False,
        do_room_correction=False,
        do_headphone_compensation=False,
        do_diffuse_field_compensation=True,
        do_equalization=False,
        test_signal=test_signal,
        channel_balance=None,
        fs=None,
    )
    output_path = os.path.join(dir_path, "responses.wav")
    assert os.path.exists(output_path)
    assert called["dir_path"] == dir_path


def test_x_curve_options(tmp_path, dummy_capture, monkeypatch):
    dir_path, test_signal = dummy_capture("9.1.6")
    monkeypatch.setattr("earprint.diffuse_field_compensation", lambda *a, **k: None)
    monkeypatch.setattr("earprint.write_readme", lambda *a, **k: "")
    monkeypatch.setattr("earprint.equalization", lambda *a, **k: (None, None))
    monkeypatch.setattr("hrir.HRIR.crop_heads", lambda self, head_ms=1: None)
    called = {}

    def fake_main(**kwargs):
        called.update(kwargs)
        write_wav(os.path.join(kwargs["dir_path"], "responses.wav"), 8000, np.zeros((1, 2)))

    monkeypatch.setattr(earprint, "main", fake_main)
    earprint.main(
        dir_path=dir_path,
        plot=False,
        do_room_correction=False,
        do_headphone_compensation=False,
        do_equalization=False,
        test_signal=test_signal,
        channel_balance=None,
        fs=None,
        apply_x_curve=True,
        x_curve_type="minus3db_oct",
    )
    earprint.main(
        dir_path=dir_path,
        plot=False,
        do_room_correction=False,
        do_headphone_compensation=False,
        do_equalization=False,
        test_signal=test_signal,
        channel_balance=None,
        fs=None,
        remove_x_curve=True,
        x_curve_in_capture=True,
        x_curve_type="minus1p5db_oct",
    )
    assert os.path.exists(os.path.join(dir_path, "responses.wav"))
    assert called["apply_x_curve"] is True