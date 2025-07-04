import importlib
import json


def test_save_and_load_room_preset(tmp_path, monkeypatch):
    preset_file = tmp_path / "rooms.json"
    monkeypatch.setenv("EARPRINT_ROOM_PRESETS", str(preset_file))
    import room_presets

    importlib.reload(room_presets)
    from models import RoomPreset

    preset = RoomPreset(brir_dir="brirs", measurement_dir="meas", notes="n")
    room_presets.save_room_preset("test", preset, str(preset_file))
    presets = room_presets.load_room_presets(str(preset_file))
    assert "test" in presets
    assert presets["test"]["brir_dir"] == "brirs"

    room_presets.delete_room_preset("test", str(preset_file))
    presets = room_presets.load_room_presets(str(preset_file))
    assert presets == {}


def test_import_room_preset(tmp_path):
    preset_file = tmp_path / "rooms.json"
    src = tmp_path / "room.json"
    json.dump({"brir_dir": "b", "measurement_dir": "m", "name": "src"}, src.open("w"))
    import room_presets

    room_presets.import_room_preset(str(src), file_path=str(preset_file))
    presets = room_presets.load_room_presets(str(preset_file))
    assert presets["src"]["brir_dir"] == "b"

    room_presets.import_room_preset(
        str(src), name="partial", fields=["measurement_dir"], file_path=str(preset_file)
    )
    presets = room_presets.load_room_presets(str(preset_file))
    assert presets["partial"] == {"measurement_dir": "m"}
