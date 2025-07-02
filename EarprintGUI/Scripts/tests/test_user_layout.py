import os
import importlib

import json

import pytest

# Set custom env var for layout file


def test_save_and_load_custom_layout(tmp_path, monkeypatch):
    preset_file = tmp_path / 'preset.json'
    monkeypatch.setenv('EARPRINT_LAYOUT_PRESETS', str(preset_file))
    import constants

    importlib.reload(constants)

    constants.save_user_layout_preset('test', [['FL'], ['FR']], str(preset_file))
    loaded = constants.load_user_layout_presets(str(preset_file))
    assert 'test' in loaded
    assert loaded['test'] == [['FL'], ['FR']]

    # Reload constants to ensure automatic inclusion
    importlib.reload(constants)
    assert 'test' in constants.SPEAKER_LAYOUTS


def test_register_user_layout(tmp_path):
    import constants
    import importlib

    preset = {'custom': [['FL'], ['FR']]}
    constants.register_user_layouts(preset)
    assert 'custom' in constants.SPEAKER_LAYOUTS
    assert constants.SPEAKER_LAYOUT_INDEXES['custom'] == [(0,), (1,)]

    importlib.reload(constants)
    assert 'custom' not in constants.SPEAKER_LAYOUTS


def test_load_and_register_user_layouts(tmp_path):
    import constants
    import importlib

    file = tmp_path / 'layouts.json'
    with open(file, 'w', encoding='utf-8') as f:
        json.dump({'foo': [['FL'], ['FR']]}, f)

    constants.load_and_register_user_layouts(str(file))
    assert 'foo' in constants.SPEAKER_LAYOUTS
    assert constants.SPEAKER_LAYOUT_INDEXES['foo'] == [(0,), (1,)]

    importlib.reload(constants)
    assert 'foo' not in constants.SPEAKER_LAYOUTS