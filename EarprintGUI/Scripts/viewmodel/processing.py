from typing import List, Optional
import subprocess
import sys
import os

from models import ProcessingSettings


class ProcessingViewModel:
    """ViewModel for running the main processing pipeline."""

    def run(self, settings: ProcessingSettings) -> subprocess.CompletedProcess:
        args: List[str] = [
            sys.executable,
            "earprint.py",
            "--dir_path",
            settings.measurement_dir,
        ]
        if settings.test_signal:
            args.extend(["--input", settings.test_signal])
        if settings.decay_time:
            args.extend(["--decay", settings.decay_time])
        if settings.target_level:
            args.extend(["--target_level", settings.target_level])
        if settings.channel_balance_enabled:
            args.extend(["--channel_balance", settings.channel_balance])
        if settings.specific_limit_enabled and settings.specific_limit:
            args.extend(["--specific_limit", settings.specific_limit])
        if settings.generic_limit_enabled and settings.generic_limit:
            args.extend(["--generic_limit", settings.generic_limit])
        if settings.fr_combination_enabled and settings.fr_combination_method:
            args.extend(["--fr_combination_method", settings.fr_combination_method])
        if settings.room_correction:
            args.extend(["--room_target", settings.room_target])
            if settings.mic_calibration:
                if not os.path.isfile(settings.mic_calibration):
                    raise FileNotFoundError("Mic calibration file not found")
                args.extend(["--room_mic_calibration", settings.mic_calibration])
        if settings.enable_compensation:
            args.append("--compensation")
            if settings.headphone_eq_enabled and settings.headphone_file:
                args.extend(["--headphones", settings.headphone_file])
            if not settings.headphone_eq_enabled:
                args.append("--no_headphone_compensation")
            if settings.compensation_type:
                args.append(settings.compensation_type)
        if settings.diffuse_field:
            args.append("--diffuse_field_compensation")
        if settings.x_curve_action == "Apply X-Curve":
            args.append("--apply_x_curve")
        elif settings.x_curve_action == "Remove X-Curve":
            args.append("--remove_x_curve")
        if settings.x_curve_action != "None" and settings.x_curve_type:
            args.extend(["--x_curve_type", settings.x_curve_type])
        if settings.x_curve_in_capture:
            args.append("--x_curve_in_capture")
        if settings.interactive_delays:
            args.append("--interactive_delays")
        else:
            pos_file = os.path.join(settings.measurement_dir, "speaker_positions.json")
            if os.path.isfile(pos_file):
                from viewmodel.layout import LayoutViewModel

                delay_file = os.path.join(settings.measurement_dir, "speaker_delays.json")
                try:
                    LayoutViewModel().delays_from_positions(pos_file, delay_file)
                    args.extend(["--delay-file", delay_file])
                except OSError:
                    pass

        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result