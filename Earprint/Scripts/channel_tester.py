# See NOTICE.md for license and attribution details.
"""Play a test signal on a specific output channel."""

import argparse
import numpy as np
import sounddevice as sd


def pink_noise(n: int) -> np.ndarray:
    """Generate approximate pink noise using filtering."""
    rows = 16
    array = np.random.randn(rows, n)
    array = np.cumsum(array, axis=1)
    weight = 2 ** np.arange(rows)[:, None]
    data = np.sum(array / weight, axis=0)
    data /= np.max(np.abs(data))
    return data


def sine_wave(freq: float, n: int, fs: int) -> np.ndarray:
    t = np.arange(n) / fs
    return np.sin(2 * np.pi * freq * t)


def main() -> None:
    parser = argparse.ArgumentParser(description="Channel test signal player")
    parser.add_argument("--device", required=False, help="Output device index or name")
    parser.add_argument("--channels", type=int, required=True, help="Total output channels")
    parser.add_argument("--channel", type=int, required=True, help="Channel to play (0-based)")
    parser.add_argument("--tone", action="store_true", help="Play 1 kHz tone instead of pink noise")
    parser.add_argument("--duration", type=float, default=1.0, help="Duration in seconds")
    args = parser.parse_args()

    device = None  # Default to system default
    
    if args.device is not None:
        try:
            # Try to convert to integer (device index like 0, 1, 2...)
            device = int(args.device)
            print(f"Using device index: {device}")
        except ValueError:
            # If it's not a number, treat it as a device name
            device = args.device
            print(f"Using device name: {device}")
    else:
        print("Using system default audio device")

    fs = 48000
    n = int(args.duration * fs)
    amp = 10 ** (-20 / 20)

    signal = sine_wave(1000.0, n, fs) if args.tone else pink_noise(n)
    signal *= amp

    # Query the actual device to get its real channel count
    device_info = sd.query_devices(device, 'output')
    actual_channels = device_info['max_output_channels']

    print(f"Device has {actual_channels} output channels, requested {args.channels}")

    # Use the minimum of requested channels and actual device channels
    channels_to_use = min(args.channels, actual_channels)

    # If the requested channel is beyond what the device supports, use channel 0
    channel_to_play = args.channel if args.channel < channels_to_use else 0

    print(f"Playing on channel {channel_to_play} of {channels_to_use} total channels")

    data = np.zeros((n, channels_to_use), dtype=np.float32)
    data[:, channel_to_play] = signal

    sd.play(data, fs, device=device, blocking=True)


if __name__ == "__main__":
    main()
