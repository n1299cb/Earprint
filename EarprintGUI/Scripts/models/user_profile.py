from dataclasses import dataclass, field
from typing import List


@dataclass
class UserProfile:
    """Profile storing personalized BRIR, EQ, and device settings."""

    brir_dir: str
    tracking_calibration: str
    output_routing: List[int] = field(default_factory=list)
    latency: int = 0
    headphone_file: str = ""
    playback_device: str = ""