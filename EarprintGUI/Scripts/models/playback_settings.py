from dataclasses import dataclass


@dataclass
class PlaybackSettings:
    """Settings for real-time convolution playback."""

    brir_dir: str
    osc_port: int = 9000
    samplerate: int = 48000
    blocksize: int = 1024
    latency: float = 0.0
    smoothing_ms: float = 50.0