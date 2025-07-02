# See NOTICE.md for license and attribution details.

import sys
import argparse
import numpy as np
import sounddevice as sd
import queue
import time
import inspect


class LevelMonitor:
    """Simple real-time level monitor."""

    def __init__(
        self,
        device=None,
        samplerate=48000,
        channels=1,
        blocksize=1024,
        *,
        latency=None,
        loopback=False,
    ):
        self.device = device
        self.samplerate = samplerate
        self.channels = channels
        self.blocksize = blocksize
        self.latency = latency
        self.loopback = loopback
        self.queue = queue.Queue()
        self.running = False

    def _callback(self, indata, frames, time_info, status):
        if status:
            print(status, file=sys.stderr)
        rms = np.sqrt(np.mean(np.square(indata)))
        db = 20 * np.log10(rms) if rms > 0 else -np.inf
        self.queue.put(db)

    def start(self, duration=None, callback=None):
        """Start monitoring. If ``callback`` is None, prints dB levels."""
        self.running = True
        stream_kwargs = {
            "device": self.device,
            "channels": self.channels,
            "samplerate": self.samplerate,
            "blocksize": self.blocksize,
            "callback": self._callback,
            "latency": self.latency,
        }

        try:
            if "loopback" in inspect.signature(sd.InputStream).parameters:
                stream_kwargs["loopback"] = self.loopback
        except Exception:
            pass

        with sd.InputStream(**stream_kwargs):
            start_time = time.time()
            while self.running:
                try:
                    level = self.queue.get(timeout=0.1)
                except queue.Empty:
                    if duration is not None and time.time() - start_time > duration:
                        break
                    continue
                if not self.running:
                    break
                if callback:
                    callback(level)
                else:
                    print(f"{level:.2f}")
                if duration is not None and time.time() - start_time > duration:
                    break
        self.running = False

    def stop(self):
        """Stop the monitor loop."""
        self.running = False


def main():
    parser = argparse.ArgumentParser(description="Live input level monitor")
    parser.add_argument("--device", type=str, default=None, help="Input device name or index")
    parser.add_argument("--channels", type=int, default=1, help="Number of input channels")
    parser.add_argument("--samplerate", type=int, default=48000, help="Sampling rate")
    parser.add_argument("--blocksize", type=int, default=1024, help="Block size for stream")
    parser.add_argument("--duration", type=float, default=None, help="Optional duration in seconds")
    parser.add_argument(
        "--loopback",
        action="store_true",
        help="Enable loopback mode for output monitoring if supported",
    )
    args = parser.parse_args()

    monitor = LevelMonitor(
        device=args.device,
        samplerate=args.samplerate,
        channels=args.channels,
        blocksize=args.blocksize,
        loopback=args.loopback,
    )
    monitor.start(duration=args.duration)


if __name__ == "__main__":
    main()