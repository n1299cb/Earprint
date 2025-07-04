import importlib
import json

import pytest


def test_save_and_load_profile(tmp_path, monkeypatch):
    profiles_file = tmp_path / "profiles.json"
    monkeypatch.setenv("EARPRINT_PROFILES", str(profiles_file))
    import user_profiles

    importlib.reload(user_profiles)
    from models import UserProfile

    profile = UserProfile(
        brir_dir="brirs",
        tracking_calibration="track.cal",
        output_routing=[0, 1],
        latency=128,
        headphone_file="eq.csv",
        playback_device="dac",
    )
    user_profiles.save_profile("test", profile, str(profiles_file))
    profiles = user_profiles.load_profiles(str(profiles_file))
    assert "test" in profiles
    assert profiles["test"]["brir_dir"] == "brirs"
    assert profiles["test"]["headphone_file"] == "eq.csv"
    assert profiles["test"]["playback_device"] == "dac"

    user_profiles.delete_profile("test", str(profiles_file))
    profiles = user_profiles.load_profiles(str(profiles_file))
    assert profiles == {}


def test_import_profile(tmp_path):
    profiles_file = tmp_path / "profiles.json"
    src = tmp_path / "profile.json"
    json.dump({"brir_dir": "x", "latency": 1, "name": "src"}, src.open("w"))
    import user_profiles

    user_profiles.import_profile(str(src), file_path=str(profiles_file))
    profiles = user_profiles.load_profiles(str(profiles_file))
    assert profiles["src"]["latency"] == 1

    user_profiles.import_profile(str(src), name="piece", fields=["brir_dir"], file_path=str(profiles_file))
    profiles = user_profiles.load_profiles(str(profiles_file))
    assert profiles["piece"] == {"brir_dir": "x"}