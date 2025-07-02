import subprocess
import json
import pytest

from viewmodel import ProcessingViewModel, RecordingViewModel, LayoutViewModel
from models import ProcessingSettings, RecorderSettings


def test_processing_vm_builds_command(monkeypatch, tmp_path):
    captured = {}

    def fake_run(args, stdout=None, stderr=None, text=None):
        captured["args"] = args
        return subprocess.CompletedProcess(args=args, returncode=0, stdout="ok", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    settings = ProcessingSettings(
        measurement_dir=str(tmp_path),
        test_signal="signal.wav",
        channel_balance_enabled=True,
        channel_balance="avg",
    )
    vm = ProcessingViewModel()
    result = vm.run(settings)

    assert "earprint.py" in captured["args"]
    assert "--channel_balance" in captured["args"]
    assert result.stdout == "ok"


def test_layout_vm_select(monkeypatch):
    captured = {}

    def fake_select(name):
        captured["name"] = name
        return "1.0", [["FL"]]

    monkeypatch.setattr("viewmodel.layout.select_layout", fake_select)

    vm = LayoutViewModel()
    layout = vm.select_layout("1.0")

    assert captured["name"] == "1.0"
    assert layout == ("1.0", [["FL"]])


def test_layout_vm_serialize(tmp_path):
    vm = LayoutViewModel()
    positions = {"FL": (50.0, 0.0)}
    data = vm.serialize_positions(positions)
    assert data[0]["name"] == "FL"
    assert data[0]["dist"] == 1.0


def test_processing_vm_missing_calibration(tmp_path):
    settings = ProcessingSettings(
        measurement_dir=str(tmp_path),
        room_correction=True,
        room_target="target.wav",
        mic_calibration=str(tmp_path / "missing.cal"),
    )
    vm = ProcessingViewModel()
    with pytest.raises(FileNotFoundError):
        vm.run(settings)


def test_recording_vm_builds_command(monkeypatch, tmp_path):
    captured = {}

    def fake_run(args, stdout=None, stderr=None, text=None):
        captured["args"] = args
        return subprocess.CompletedProcess(args=args, returncode=0, stdout="ok", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    settings = RecorderSettings(
        measurement_dir=str(tmp_path),
        test_signal="sig.wav",
        playback_device="1",
        recording_device="2",
        output_channels=[0, 1],
        input_channels=[2, 3],
        output_file="out.wav",
    )
    vm = RecordingViewModel()
    result = vm.run_recorder(settings)

    assert "recorder.py" in captured["args"]
    assert "--output_file" in captured["args"]
    assert result.stdout == "ok"


def test_processing_vm_interactive_delays(monkeypatch, tmp_path):
    captured = {}

    def fake_run(args, stdout=None, stderr=None, text=None):
        captured["args"] = args
        return subprocess.CompletedProcess(args=args, returncode=0, stdout="ok", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    settings = ProcessingSettings(
        measurement_dir=str(tmp_path),
        test_signal="signal.wav",
        interactive_delays=True,
    )
    vm = ProcessingViewModel()
    vm.run(settings)

    assert "--interactive_delays" in captured["args"]


def test_processing_vm_saved_delays(monkeypatch, tmp_path):
    pos_file = tmp_path / "speaker_positions.json"
    json.dump([{"name": "FL", "az": 0, "dist": 1.0}], pos_file.open("w"))

    captured = {}

    def fake_run(args, stdout=None, stderr=None, text=None):
        captured["args"] = args
        return subprocess.CompletedProcess(args=args, returncode=0, stdout="ok", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    def fake_delays(self, pos, out):
        captured["pos"] = pos
        captured["out"] = out

    from viewmodel.layout import LayoutViewModel as LV

    monkeypatch.setattr(LV, "delays_from_positions", fake_delays)

    settings = ProcessingSettings(
        measurement_dir=str(tmp_path),
        test_signal="signal.wav",
    )
    vm = ProcessingViewModel()
    vm.run(settings)

    assert "--delay-file" in captured["args"]
    assert captured["pos"] == str(pos_file)