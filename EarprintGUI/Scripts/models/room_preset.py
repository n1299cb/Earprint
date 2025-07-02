from dataclasses import dataclass


@dataclass
class RoomPreset:
    """Store BRIR directory and measurement metadata."""

    brir_dir: str
    measurement_dir: str
    notes: str = ""
    measurement_date: str = ""
