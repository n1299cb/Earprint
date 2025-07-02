from dataclasses import dataclass
from constants import DEFAULT_TEST_SIGNAL, DEFAULT_MEASUREMENT_DIR


@dataclass
class MeasurementSetup:
    """Data model representing measurement setup configuration."""

    test_signal: str = DEFAULT_TEST_SIGNAL
    measurement_dir: str = DEFAULT_MEASUREMENT_DIR