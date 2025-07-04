import os
from dataclasses import dataclass, field
from typing import List, Optional

from models.measurement_setup import MeasurementSetup


@dataclass
class MeasurementSetupViewModel:
    """ViewModel for managing measurement setup state and validation."""

    setup: MeasurementSetup = field(default_factory=MeasurementSetup)

    def update(self, test_signal: Optional[str] = None, measurement_dir: Optional[str] = None) -> None:
        """Update underlying setup model with new values."""
        if test_signal is not None:
            self.setup.test_signal = test_signal
        if measurement_dir is not None:
            self.setup.measurement_dir = measurement_dir

    def validate_paths(self, test_signal: Optional[str] = None, measurement_dir: Optional[str] = None) -> List[str]:
        """Validate the provided paths or current model state and return invalid field names."""
        if test_signal is not None or measurement_dir is not None:
            self.update(test_signal, measurement_dir)

        errors = []
        if not os.path.isfile(self.setup.test_signal):
            errors.append("test_signal")
        if not os.path.isdir(self.setup.measurement_dir):
            errors.append("measurement_dir")
        return errors

    def file_exists(self, path: str) -> bool:
        """Return True if the given file path exists."""
        return os.path.isfile(path)

    def directory_exists(self, path: str) -> bool:
        """Return True if the given directory path exists."""
        return os.path.isdir(path)

    # --- New helper methods for complex directory validation ---

    def missing_files(self, base_dir: str, files: List[str]) -> List[str]:
        """Return a list of required files that are missing under ``base_dir``."""
        missing: List[str] = []
        for name in files:
            path = os.path.join(base_dir, name)
            if not os.path.isfile(path):
                missing.append(path)
        return missing

    def missing_subdirs(self, base_dir: str, subdirs: List[str]) -> List[str]:
        """Return a list of required subdirectories that are missing."""
        missing: List[str] = []
        for name in subdirs:
            path = os.path.join(base_dir, name)
            if not os.path.isdir(path):
                missing.append(path)
        return missing

    def validate_structure(self, base_dir: str, structure: dict[str, List[str]]) -> List[str]:
        """Validate nested directory structure.

        ``structure`` maps relative directory paths to a list of required file
        names. Missing directories or files are returned as a list of paths.
        """
        missing: List[str] = []
        for subdir, files in structure.items():
            dir_path = os.path.join(base_dir, subdir)
            if not os.path.isdir(dir_path):
                missing.append(dir_path)
                continue
            for name in files:
                path = os.path.join(dir_path, name)
                if not os.path.isfile(path):
                    missing.append(path)
        return missing