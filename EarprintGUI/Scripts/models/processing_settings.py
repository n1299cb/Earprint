from dataclasses import dataclass
from typing import List


@dataclass
class ProcessingSettings:
    measurement_dir: str
    test_signal: str = ""
    decay_time: str = ""
    target_level: str = ""
    channel_balance_enabled: bool = False
    channel_balance: str = ""
    specific_limit_enabled: bool = False
    specific_limit: str = ""
    generic_limit_enabled: bool = False
    generic_limit: str = ""
    fr_combination_enabled: bool = False
    fr_combination_method: str = ""
    room_correction: bool = False
    room_target: str = ""
    mic_calibration: str = ""
    enable_compensation: bool = False
    headphone_eq_enabled: bool = False
    headphone_file: str = ""
    compensation_type: str = ""
    diffuse_field: bool = False
    x_curve_action: str = "None"
    x_curve_type: str = ""
    x_curve_in_capture: bool = False
    interactive_delays: bool = False