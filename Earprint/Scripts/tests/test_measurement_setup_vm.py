import os
from viewmodel import MeasurementSetupViewModel


def test_validate_paths(tmp_path):
    vm = MeasurementSetupViewModel()

    # Non-existing paths should return both errors
    errors = vm.validate_paths('missing.wav', tmp_path / 'none')
    assert 'test_signal' in errors
    assert 'measurement_dir' in errors

    # Create valid paths
    signal = tmp_path / 'tone.wav'
    signal.write_text('data')
    errors = vm.validate_paths(str(signal), str(tmp_path))
    assert errors == []


def test_file_and_directory_checks(tmp_path):
    vm = MeasurementSetupViewModel()

    existing_file = tmp_path / "a.wav"
    existing_file.write_text("data")
    missing_file = tmp_path / "missing.wav"

    existing_dir = tmp_path / "d"
    existing_dir.mkdir()
    missing_dir = tmp_path / "missing"

    assert vm.file_exists(str(existing_file))
    assert not vm.file_exists(str(missing_file))

    assert vm.directory_exists(str(existing_dir))
    assert not vm.directory_exists(str(missing_dir))


def test_directory_helpers(tmp_path):
    vm = MeasurementSetupViewModel()

    # Prepare file and folder structure
    sub = tmp_path / "sub"
    sub.mkdir()
    (tmp_path / "a.wav").write_text("data")
    (sub / "b.wav").write_text("data")

    # missing_files should report absent files
    missing = vm.missing_files(str(tmp_path), ["a.wav", "c.wav"])
    assert str(tmp_path / "c.wav") in missing
    assert str(tmp_path / "a.wav") not in missing

    # missing_subdirs should report absent directories
    missing = vm.missing_subdirs(str(tmp_path), ["sub", "missing"])
    assert str(tmp_path / "missing") in missing
    assert str(tmp_path / "sub") not in missing

    # validate_structure checks nested layout
    structure = {
        "": ["a.wav"],
        "sub": ["b.wav", "missing.wav"],
    }
    missing = vm.validate_structure(str(tmp_path), structure)
    assert str(sub / "missing.wav") in missing

from models import MeasurementSetup
from constants import DEFAULT_TEST_SIGNAL, DEFAULT_MEASUREMENT_DIR

def test_measurement_setup_defaults():
    setup = MeasurementSetup()
    assert setup.test_signal == DEFAULT_TEST_SIGNAL
    assert setup.measurement_dir == DEFAULT_MEASUREMENT_DIR