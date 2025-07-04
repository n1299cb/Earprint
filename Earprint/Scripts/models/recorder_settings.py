from dataclasses import dataclass
from typing import List


@dataclass
class RecorderSettings:
    measurement_dir: str
    test_signal: str
    playback_device: str
    recording_device: str
    output_channels: List[int]
    input_channels: List[int]
    output_file: str = ""