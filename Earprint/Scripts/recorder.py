# See NOTICE.md for license and attribution details.

"""Audio recording utilities used by the capture workflow."""

import os
import re

try:
    import sounddevice as sd
except OSError:  # pragma: no cover - depends on system libs
    # Provide a minimal stub when PortAudio is unavailable so that unit tests can
    # import this module without requiring the native library. Only the
    # functions accessed during testing are implemented.
    from types import SimpleNamespace

    sd = SimpleNamespace(
        rec=lambda *a, **k: None,
        play=lambda *a, **k: None,
        wait=lambda: None,
        query_devices=lambda *a, **k: [],
        query_hostapis=lambda: [],
        default=SimpleNamespace(device=(0, 0)),
    )
from utils import read_wav, write_wav
import numpy as np
from threading import Thread
import argparse
import time
from typing import Callable, Optional
from constants import SPEAKER_NAMES, SMPTE_ORDER


class DeviceNotFoundError(Exception):
    """Raised when an audio device cannot be found or doesn't meet requirements."""

    def __init__(
        self,
        message: Optional[str] = None,
        *,
        device_name: Optional[str] = None,
        kind: Optional[str] = None,
        host_api: Optional[str] = None,
        min_channels: Optional[int] = None,
    ) -> None:
        self.device_name = device_name
        self.kind = kind
        self.host_api = host_api
        self.min_channels = min_channels

        if message is None:
            parts = []
            if kind:
                parts.append(f"{kind} device")
            else:
                parts.append("Device")
            if device_name:
                parts.append(f'"{device_name}"')
            if host_api:
                parts.append(f'with host API "{host_api}"')
            if min_channels is not None:
                parts.append(f"with at least {min_channels} channels")
            message = " ".join(parts) + " not found."

        super().__init__(message)


def record_target(file_path, length, fs, channels=2, append=False, output_file=None, report_file=None):
    """Records audio and writes it to a file.

    Args:
        file_path: Path to output file
        length: Audio recording length in samples
        fs: Sampling rate
        channels: Number of channels in the recording
        append: Add track(s) to an existing file? Silence will be added to end of each track to make all equal in
                length
        output_file: Optional custom file path for recording output
        report_file: Optional path for recording quality report. Defaults to "<record>_report.txt".

    Returns:
        None
    """
    recording = sd.rec(length, samplerate=fs, channels=channels, blocking=True)
    recording = np.transpose(recording)
    peak = np.max(np.abs(recording))
    max_gain = 20 * np.log10(peak) if peak > 0 else -np.inf
    headroom = -max_gain

    # Estimate noise floor from the last 10 %% of the recording
    tail_start = int(recording.shape[1] * 0.9)
    tail = recording[:, tail_start:]
    noise_rms = np.sqrt(np.mean(tail**2))
    noise_floor = 20 * np.log10(noise_rms) if noise_rms > 0 else -np.inf
    if append and os.path.isfile(file_path):
        # Adding to existing file, read the file
        _fs, data = read_wav(file_path, expand=True)
        # Zero pad shorter to the length of the longer
        if recording.shape[1] > data.shape[1]:
            n = recording.shape[1] - data.shape[1]
            data = np.pad(data, [(0, 0), (0, n)])
        elif data.shape[1] > recording.shape[1]:
            recording = np.pad(data, [(0, 0), (0, data.shape[1] - recording.shape[1])])
        # Add recording to the end of the existing data
        recording = np.vstack([data, recording])
    if output_file:
        file_path = output_file

    write_wav(file_path, fs, recording)
    print(f"Headroom: {headroom:.1f} dB")

    if peak >= 1.0:
        print("Warning: clipping detected!")
    if noise_floor > -50:
        print(f"Warning: high noise floor ({noise_floor:.1f} dBFS)")

    if report_file:
        with open(report_file, "w") as f:
            f.write(f"Peak level: {max_gain:.1f} dBFS\n")
            f.write(f"Headroom: {headroom:.1f} dB\n")
            f.write(f"Noise floor: {noise_floor:.1f} dBFS\n")
            f.write(f'Clipping: {"yes" if peak >= 1.0 else "no"}\n')
            f.write(f'Excess noise: {"yes" if noise_floor > -50 else "no"}\n')


def get_host_api_names():
    """Gets names of available host APIs in a list"""
    return [hostapi["name"] for hostapi in sd.query_hostapis()]


def get_device(device_name, kind, host_api=None, min_channels=1):
    """Finds device with name, kind and host API

    Args:
        device_name: Device name
        kind: Device type. "input" or "output"
        host_api: Host API name
        min_channels: Minimum number of channels in the device

    Returns:
        Device, None if no device was found which satisfies the parameters
    """
    if device_name is None:
        raise TypeError("Device name is required and cannot be None")
    if kind is None:
        raise TypeError("Kind is required and cannot be None")
    # Available host APIs
    host_api_names = get_host_api_names()

    for i in range(len(host_api_names)):
        host_api_names[i] = host_api_names[i].replace("Windows ", "")

    if host_api is not None:
        host_api = host_api.replace("Windows ", "")

    # Host API check pattern
    host_api_pattern = f'({"|".join([re.escape(name) for name in host_api_names])})$'

    # Find with the given name
    device = None
    if re.search(host_api_pattern, device_name):
        # Host API in the name, this should return only one device
        device = sd.query_devices(device_name, kind=kind)
        if device[f"max_{kind}_channels"] < min_channels:
            # Channel count not satisfied
            raise DeviceNotFoundError(
                f'Found {kind} device "{device["name"]} {host_api_names[device["hostapi"]]}" '
                f"but minimum number of channels is not satisfied.",
                device_name=device["name"],
                kind=kind,
                host_api=host_api_names[device["hostapi"]],
                min_channels=min_channels,
            )
    elif not re.search(host_api_pattern, device_name) and host_api is not None:
        # Host API not specified in the name but host API is given as parameter
        try:
            # This should give one or zero devices
            device = sd.query_devices(f"{device_name} {host_api}", kind=kind)
        except ValueError:
            # Zero devices
            raise DeviceNotFoundError(
                f'No device found with name "{device_name}" and host API "{host_api}".',
                device_name=device_name,
                kind=kind,
                host_api=host_api,
                min_channels=min_channels,
            )
        if device[f"max_{kind}_channels"] < min_channels:
            # Channel count not satisfied
            raise DeviceNotFoundError(
                f'Found {kind} device "{device["name"]} {host_api_names[device["hostapi"]]}" '
                f"but minimum number of channels is not satisfied.",
                device_name=device["name"],
                kind=kind,
                host_api=host_api_names[device["hostapi"]],
                min_channels=min_channels,
            )
    else:
        # Host API not in the name and host API is not given as parameter
        host_api_preference = [x for x in ["DirectSound", "MME", "WASAPI"] if x in host_api_names]
        for host_api_name in host_api_preference:
            # Looping in the order of preference
            try:
                device = sd.query_devices(f"{device_name} {host_api_name}", kind=kind)
                if device[f"max_{kind}_channels"] >= min_channels:
                    break
                else:
                    device = None
            except ValueError:
                pass
        if device is None:
            raise DeviceNotFoundError(
                "Could not find any device which satisfies minimum channel count.",
                device_name=device_name,
                kind=kind,
                min_channels=min_channels,
            )

    return device


def get_devices(input_device=None, output_device=None, host_api=None, min_channels=1):
    """Finds input and output devices

    Args:
        input_device: Input device name. System default is used if not given.
        output_device: Output device name. System default is used if not given.
        host_api: Host API name
        min_channels: Minimum number of output channels that the output device needs to support

    Returns:
        - Input device object
        - Output device object
    """
    # Find devices
    devices = sd.query_devices()

    # Select input device
    if input_device is None:
        # Not given, use default
        input_device = devices[sd.default.device[0]]["name"]
    input_device = get_device(input_device, "input", host_api=host_api)

    # Select output device
    if output_device is None:
        # Not given, use default
        output_device = devices[sd.default.device[1]]["name"]
    output_device = get_device(output_device, "output", host_api=host_api, min_channels=min_channels)

    return input_device, output_device


def set_default_devices(input_device, output_device):
    """Sets sounddevice default devices

    Args:
        input_device: Input device object
        output_device: Output device object

    Returns:
        - Input device name and host API as string
        - Output device name and host API as string
    """
    host_api_names = get_host_api_names()
    input_device_str = f'{input_device["name"]} {host_api_names[input_device["hostapi"]]}'
    output_device_str = f'{output_device["name"]} {host_api_names[output_device["hostapi"]]}'
    sd.default.device = (input_device_str, output_device_str)
    return input_device_str, output_device_str


def play_and_record(
    play: Optional[str] = None,
    record: Optional[str] = None,
    input_device: Optional[int] = None,
    output_device: Optional[int] = None,
    host_api: Optional[str] = None,
    channels: int = 2,
    append: bool = False,
    output_file: Optional[str] = None,
    report_file: Optional[str] = None,
    progress_callback: Optional[Callable[[float, float], None]] = None,
) -> None:
    """Plays one file and records another at the same time

    Args:
        play: File path to playback file
        record: File path to output recording file
        input_device: Number of the input device as seen by sounddevice
        output_device: Number of the output device as seen by sounddevice
        host_api: Host API name
        channels: Number of output channels
        append: Add track(s) to an existing file? Silence will be added to end of each track to make all equal in
                length
        report_file: Path to write recording quality report. Defaults to "<record>_report.txt".

    Returns:
        None
    """
    # Create output directory
    out_dir, out_file = os.path.split(os.path.abspath(record))
    os.makedirs(out_dir, exist_ok=True)

    if report_file is None:
        base = os.path.splitext(os.path.basename(output_file or record))[0]
        report_file = os.path.join(out_dir, f"{base}_report.txt")

    # Validate speaker layout from filename
    speaker_names = os.path.splitext(out_file)[0].split(",")
    if len(speaker_names) != channels:
        print(f"Warning: {len(speaker_names)} speaker labels in filename, but {channels} output channels specified.")
        layout_name = None
        expected_order = None
        for name, order in SMPTE_ORDER.items():
            if len(order) == channels:
                layout_name = name
                expected_order = ",".join(SPEAKER_NAMES[i] for i in order)
                break
        if layout_name:
            print(f"Expected SMPTE layout {layout_name} order:\n  {expected_order}")
        else:
            print("No matching SMPTE layout for the given channel count.")

    # Read playback file
    fs, data = read_wav(play)
    n_channels = data.shape[0]

    # Find and set devices as default
    input_device, output_device = get_devices(
        input_device=input_device, output_device=output_device, host_api=host_api, min_channels=n_channels
    )
    input_device_str, output_device_str = set_default_devices(input_device, output_device)

    print(f'Input device:  "{input_device_str}"')
    print(f'Output device: "{output_device_str}"')

    recorder = Thread(
        target=record_target,
        args=(record, data.shape[1], fs),
        kwargs={
            "channels": channels,
            "append": append,
            "output_file": output_file,
            "report_file": report_file,
        },
    )
    recorder.start()
    duration = data.shape[1] / fs
    sd.play(np.transpose(data), samplerate=fs, blocking=False)
    start = time.time()
    if progress_callback:
        progress_callback(0.0, duration)
    while True:
        elapsed = time.time() - start
        if progress_callback:
            progress = min(elapsed / duration, 1.0)
            progress_callback(progress, max(duration - elapsed, 0.0))
        if elapsed >= duration:
            break
        time.sleep(0.1)
    sd.wait()
    recorder.join()
    if progress_callback:
        progress_callback(1.0, 0.0)


def create_cli():
    """Create command line interface

    Returns:
        Parsed CLI arguments
    """
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--play", type=str, required=True, help="File path to WAV file to play.")
    arg_parser.add_argument(
        "--record",
        type=str,
        required=True,
        help='File path to write the recording. This must have ".wav" extension and be either'
        '"headphones.wav" or any combination of supported speaker names separated by commas '
        "eg. FL,FC,FR.wav to be recognized by Earprint as a recording file. It's "
        "convenient to point the file path directly to the recording directory such as "
        '"data\\my_hrir\\FL,FR.wav".',
    )
    arg_parser.add_argument(
        "--input_device",
        type=str,
        default=argparse.SUPPRESS,
        help='Name or number of the input device. Use "python -m sounddevice to '
        "find out which devices are available. It's possible to add host API at the end of "
        "the input device name separated by space to specify which host API to use. For "
        'example: "Zoom H1n DirectSound".',
    )
    arg_parser.add_argument(
        "--output_device",
        type=str,
        default=argparse.SUPPRESS,
        help='Name or number of the output device. Use "python -m sounddevice to '
        "find out which devices are available. It's possible to add host API at the end of "
        "the output device name separated by space to specify which host API to use. For "
        'example: "Zoom H1n WASAPI"',
    )
    arg_parser.add_argument(
        "--output_file",
        type=str,
        default=None,
        help="Optional custom output filename (e.g., headphones.wav). Overrides automatic naming.",
    )
    arg_parser.add_argument(
        "--report_file", type=str, default=None, help="Optional path for recording quality report file."
    )
    arg_parser.add_argument(
        "--host_api",
        type=str,
        default=argparse.SUPPRESS,
        help="Host API name to prefer for input and output devices. Supported options on Windows "
        'are: "MME", "DirectSound" and "WASAPI". This is used when input and '
        "output devices have not been specified (using system defaults) or if they have no "
        "host API specified.",
    )
    arg_parser.add_argument("--channels", type=int, default=16, help="Number of output channels.")
    arg_parser.add_argument(
        "--append",
        action="store_true",
        help="Add track(s) to existing file? Silence will be added to the end of all tracks to "
        "make the equal in length.",
    )
    arg_parser.add_argument(
        "--print_progress",
        action="store_true",
        help="Print recording progress updates for GUI integration",
    )
    args = vars(arg_parser.parse_args())
    return args


if __name__ == "__main__":
    args = create_cli()
    if args.pop("print_progress", False):

        def progress_fn(progress: float, remaining: float) -> None:
            print(f"PROGRESS {progress:.3f} {remaining:.3f}", flush=True)

    else:
        progress_fn = None

    play_and_record(**args, progress_callback=progress_fn)
