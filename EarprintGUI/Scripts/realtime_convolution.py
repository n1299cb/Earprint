# See NOTICE.md for license and attribution details.

"""Real-time convolution engine for binaural rendering."""

from __future__ import annotations

import numpy as np
from typing import Dict, Optional, Tuple, Union

try:
    import pyfftw  # type: ignore
    from pyfftw.interfaces import numpy_fft as fft
    pyfftw.interfaces.cache.enable()
except Exception:  # pragma: no cover - optional dependency may be missing
    from numpy import fft  # type: ignore

try:
    import sounddevice as sd
except Exception:  # pragma: no cover - optional dependency may be missing
    sd = None
from utils import read_wav
import threading
from impulse_response import ImpulseResponse
from hrir import HRIR
from constants import HEXADECAGONAL_TRACK_ORDER


class RealTimeConvolver:
    """Low-latency convolution engine for binaural rendering."""

    def __init__(
        self,
        irs: Union[HRIR, Dict[Union[float, Tuple[float, float, float]], Tuple[np.ndarray, np.ndarray]]],
        samplerate: Optional[int] = None,
        block_size: int = 1024,
    ) -> None:
        self.block_size = block_size
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._yaw = 0.0
        self._pitch = 0.0
        self._roll = 0.0

        if isinstance(irs, dict):
            if samplerate is None:
                raise ValueError("samplerate must be given for BRIR dictionaries")
            self.fs = samplerate
            self.brirs: Dict[Union[float, Tuple[float, float, float]], Tuple[np.ndarray, np.ndarray]] = {
                a: (np.asarray(l), np.asarray(r)) for a, (l, r) in irs.items()
            }
            self.angles = list(self.brirs.keys())
            self._prepare_ir_fft_brirs()
            self.n_speakers = 2
        else:
            self.fs = irs.fs
            self.speakers = list(irs.irs.keys())
            self.n_speakers = len(self.speakers)
            self._prepare_ir_fft_hrir(irs)

        self.overlap = np.zeros((2, self.fft_size - self.block_size))


    def _next_pow2(self, x: int) -> int:
        return 1 << (x - 1).bit_length()

    def _prepare_ir_fft_hrir(self, hrir) -> None:
        max_len = 0
        for pair in hrir.irs.values():
            max_len = max(max_len, len(pair["left"].data), len(pair["right"].data))
        self.fft_size = self._next_pow2(self.block_size + max_len - 1)
        self.ir_fft = {}
        for name, pair in hrir.irs.items():
            self.ir_fft[name] = {}
            for ear in ("left", "right"):
                buf = np.zeros(self.fft_size)
                data = pair[ear].data
                buf[: len(data)] = data
                self.ir_fft[name][ear] = fft.rfft(buf)

    def _prepare_ir_fft_brirs(self) -> None:
        max_len = 0
        for left, right in self.brirs.values():
            max_len = max(max_len, len(left), len(right))
        self.fft_size = self._next_pow2(self.block_size + max_len - 1)
        self.ir_fft = {}
        for angle, (left, right) in self.brirs.items():
            buf_l = np.zeros(self.fft_size)
            buf_l[: len(left)] = left
            buf_r = np.zeros(self.fft_size)
            buf_r[: len(right)] = right
            self.ir_fft[angle] = {
                "left": fft.rfft(buf_l),
                "right": fft.rfft(buf_r),
            }

    def _angular_distance(self, a: float, b: float) -> float:
        """Return smallest distance between two angles in degrees."""
        diff = abs(a - b) % 360.0
        return min(diff, 360.0 - diff)

    def process_block(self, block: np.ndarray) -> np.ndarray:
        """Process single audio block.

        Args:
            block: Array ``(n_speakers, block_size)``.

        Returns:
            Stereo output block ``(2, block_size)``.
        """
        if hasattr(self, "brirs"):
            if block.shape != (2, self.block_size):
                raise ValueError("Invalid input block shape")
            buf = np.zeros((2, self.fft_size))
            buf[:, : self.block_size] = block
            buf_fft = fft.rfft(buf, axis=1)

            if len(self.angles) == 1:
                ir = self.ir_fft[self.angles[0]]
                out_l = buf_fft[0] * ir["left"]
                out_r = buf_fft[1] * ir["right"]
            else:
                if isinstance(self.angles[0], (tuple, list)):
                    orient = np.array([self._yaw, self._pitch, self._roll])
                    dists = np.array([np.linalg.norm(orient - np.array(a)) for a in self.angles], dtype=float)
                else:
                    dists = np.array([self._angular_distance(a, self._yaw) for a in self.angles], dtype=float)

                if np.any(dists == 0):
                    weights = (dists == 0).astype(float)
                else:
                    inv = 1.0 / dists
                    weights = inv / inv.sum()

                ir_l = np.zeros_like(self.ir_fft[self.angles[0]]["left"], dtype=complex)
                ir_r = np.zeros_like(ir_l)
                for w, a in zip(weights, self.angles):
                    ir_l += w * self.ir_fft[a]["left"]
                    ir_r += w * self.ir_fft[a]["right"]

                out_l = buf_fft[0] * ir_l
                out_r = buf_fft[1] * ir_r
        else:
            if block.shape != (self.n_speakers, self.block_size):
                raise ValueError("Invalid input block shape")
            buf = np.zeros((self.n_speakers, self.fft_size))
            buf[:, : self.block_size] = block
            buf_fft = fft.rfft(buf, axis=1)
            out_l = np.zeros(self.fft_size // 2 + 1, dtype=complex)
            out_r = np.zeros_like(out_l)
            for i, name in enumerate(self.speakers):
                out_l += buf_fft[i] * self.ir_fft[name]["left"]
                out_r += buf_fft[i] * self.ir_fft[name]["right"]

        y_l = fft.irfft(out_l)
        y_r = fft.irfft(out_r)

        y_l[: self.overlap.shape[1]] += self.overlap[0]
        y_r[: self.overlap.shape[1]] += self.overlap[1]

        self.overlap[0] = y_l[self.block_size :]
        self.overlap[1] = y_r[self.block_size :]

        out = np.stack([y_l[: self.block_size], y_r[: self.block_size]])


        return out

    def set_orientation(self, yaw: float, pitch: float = 0.0, roll: float = 0.0) -> None:
        """Update current head orientation."""
        self._yaw = float(yaw)
        self._pitch = float(pitch)
        self._roll = float(roll)

    def start(
        self,
        duration: Optional[float] = None,
        input_device: Optional[Union[int, str]] = None,
        output_device: Optional[Union[int, str]] = None,
        latency: float | None = None,
        host_api: Optional[str] = None,
    ) -> None:
        """Start real-time convolution in a background thread.

        Args:
            duration: Stop after this many seconds (``None`` to run indefinitely).
            input_device: Input device index or name.
            output_device: Output device index or name.
            latency: Desired latency in seconds.
            host_api: Preferred host API name (e.g. ``"Core Audio"``).
        """
        if self._thread is not None:
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self.run,
            kwargs={
                "duration": duration,
                "input_device": input_device,
                "output_device": output_device,
                "latency": latency,
                "host_api": host_api,
            },
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        """Stop the background convolution thread."""
        if self._thread is None:
            return
        self._stop.set()
        if sd:
            sd.stop()
        self._thread.join()
        self._thread = None

    def run(
        self,
        duration: Optional[float] = None,
        input_device: Optional[Union[int, str]] = None,
        output_device: Optional[Union[int, str]] = None,
        latency: float | None = None,
        host_api: Optional[str] = None,
    ) -> None:
        """Run real-time convolution using ``sounddevice`` streams.

        Args:
            duration: Stop after this many seconds (``None`` to run indefinitely).
            input_device: Input device index or name.
            output_device: Output device index or name.
            latency: Desired latency in seconds.
            host_api: Preferred host API name (e.g. ``"Core Audio"``).
        """

        if sd is None:
            raise RuntimeError("sounddevice library not available")

        def callback(indata, outdata, frames, time_info, status):
            if status:
                print(status)
            block = np.transpose(indata)
            out_block = self.process_block(block)
            outdata[:] = np.transpose(out_block)

        if host_api is not None:
            try:
                hostapis = sd.query_hostapis()
                for idx, api in enumerate(hostapis):
                    if host_api.lower() in api['name'].lower():
                        sd.default.hostapi = idx
                        break
            except Exception:
                pass

        with sd.Stream(
            samplerate=self.fs,
            blocksize=self.block_size,
            dtype="float32",
            channels=(self.n_speakers, 2),
            callback=callback,
            device=(input_device, output_device),
            latency=latency,
        ):
            if duration is None:
                while not self._stop.is_set():
                    sd.sleep(100)
            else:
                sd.sleep(int(duration * 1000))


def convolve_file(
    input_wav: str,
    output_wav: str,
    hrir,
    block_size: int = 1024,
) -> None:
    """Offline convolution helper for multi-channel files."""

    import soundfile as sf

    fs = hrir.fs
    data, fs_in = sf.read(input_wav, always_2d=True)
    if fs_in != fs:
        raise ValueError("Sampling rate mismatch")
    engine = RealTimeConvolver(hrir, block_size)
    out = []
    idx = 0
    data = np.transpose(data)
    while idx < data.shape[1]:
        block = data[:, idx : idx + block_size]
        if block.shape[1] < block_size:
            pad = np.zeros((data.shape[0], block_size - block.shape[1]))
            block = np.concatenate([block, pad], axis=1)
        out_block = engine.process_block(block)
        out.append(out_block)
        idx += block_size
    out = np.concatenate(out, axis=1)
    sf.write(output_wav, np.transpose(out), fs)


def _hrir_from_wav(file_path: str) -> HRIR:
    """Helper for loading ``hrir.wav`` into an ``HRIR`` object."""

    fs, data = read_wav(file_path, expand=True)
    estimator = type("_e", (), {"fs": fs})()
    h = HRIR(estimator)
    for ch_name, ch_data in zip(HEXADECAGONAL_TRACK_ORDER, data):
        speaker, side = ch_name.split("-")
        if speaker not in h.irs:
            h.irs[speaker] = {}
        h.irs[speaker][side] = ImpulseResponse(ch_data, fs)
    return h


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Offline BRIR convolution")
    parser.add_argument("input", help="Input multichannel WAV file")
    parser.add_argument("output", help="Output stereo WAV file")
    parser.add_argument("hrir", help="hrir.wav generated by Earprint")
    parser.add_argument("--block_size", type=int, default=1024)
    args = parser.parse_args()

    hrir_obj = _hrir_from_wav(args.hrir)
    convolve_file(args.input, args.output, hrir_obj, block_size=args.block_size)


# Backwards compatibility for earlier naming
RealtimeConvolver = RealTimeConvolver