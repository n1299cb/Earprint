import importlib
import json
import pytest


def test_save_and_load_preset(tmp_path, monkeypatch):
    preset_file = tmp_path / "processing-presets.json"
    monkeypatch.setenv("EARPRINT_PRESETS", str(preset_file))
    import preset_manager
    importlib.reload(preset_manager)
    from models import ProcessingSettings

    settings = ProcessingSettings(measurement_dir="dir")
    preset_manager.save_preset("test", settings, str(preset_file))
    presets = preset_manager.load_presets(str(preset_file))
    assert "test" in presets
    assert presets["test"]["measurement_dir"] == "dir"

    preset_manager.delete_preset("test", str(preset_file))
    presets = preset_manager.load_presets(str(preset_file))
    assert presets == {}


def test_import_preset(tmp_path):
    preset_file = tmp_path / "processing-presets.json"
    src = tmp_path / "src.json"
    json.dump({"measurement_dir": "x", "test_signal": "sig.wav", "name": "src"}, src.open("w"))
    import preset_manager

    preset_manager.import_preset(str(src), file_path=str(preset_file))
    presets = preset_manager.load_presets(str(preset_file))
    assert presets["src"]["measurement_dir"] == "x"

    preset_manager.import_preset(str(src), name="partial", fields=["test_signal"], file_path=str(preset_file))
    presets = preset_manager.load_presets(str(preset_file))
    assert presets["partial"] == {"test_signal": "sig.wav"}