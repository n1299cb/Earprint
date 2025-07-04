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
    parser.add_argument("--device", required=True, help="Output device index or name")
    parser.add_argument("--channels", type=int, required=True, help="Total output channels")
    parser.add_argument("--channel", type=int, required=True, help="Channel to play (0-based)")
    parser.add_argument("--tone", action="store_true", help="Play 1 kHz tone instead of pink noise")
    parser.add_argument("--duration", type=float, default=1.0, help="Duration in seconds")
    args = parser.parse_args()

    fs = 48000
    n = int(args.duration * fs)
    amp = 10 ** (-20 / 20)

    signal = sine_wave(1000.0, n, fs) if args.tone else pink_noise(n)
    signal *= amp

    data = np.zeros((n, args.channels), dtype=np.float32)
    if 0 <= args.channel < args.channels:
        data[:, args.channel] = signal
    else:
        raise ValueError("Invalid channel index")

    sd.play(data, fs, device=args.device, blocking=True)


if __name__ == "__main__":
    main()