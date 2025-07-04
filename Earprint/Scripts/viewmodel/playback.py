from __future__ import annotations

import os
import time
from threading import Thread
from typing import Optional

import numpy as np

from models import PlaybackSettings
from realtime_convolution import RealTimeConvolver
from tracking import HeadTracker


class PlaybackViewModel:
    """ViewModel controlling real-time playback with head tracking."""

    def __init__(self) -> None:
        self.tracker: Optional[HeadTracker] = None
        self.convolver: Optional[RealTimeConvolver] = None
        self._thread: Optional[Thread] = None
        self._running = False
        self._yaw = 0.0
        self._pitch = 0.0
        self._roll = 0.0
        self._alpha = 1.0

    def _load_brirs(self, path: str) -> dict[float, tuple[list[float], list[float]]]:
        brirs: dict[float, tuple[list[float], list[float]]] = {}
        for file in os.listdir(path):
            if not file.endswith(".npz"):
                continue
            angle = float(os.path.splitext(file)[0])
            data = np.load(os.path.join(path, file))
            brirs[angle] = (data["left"], data["right"])
        return brirs


    def _smooth_angle(self, current: float, target: float) -> float:
        diff = (target - current + 180.0) % 360.0 - 180.0
        return current + self._alpha * diff

    def play(self, settings: PlaybackSettings) -> None:
        brirs = self._load_brirs(settings.brir_dir)
        self.tracker = HeadTracker(port=settings.osc_port)
        self.convolver = RealTimeConvolver(
            brirs,
            samplerate=settings.samplerate,
            block_size=settings.blocksize,
        )
        self.tracker.start()
        self.convolver.start(latency=settings.latency)
        self._running = True
        if settings.smoothing_ms > 0:
            dt = 0.01
            tau = settings.smoothing_ms / 1000.0
            self._alpha = dt / (tau + dt)
        else:
            self._alpha = 1.0

        def _loop() -> None:
            while self._running:
                if self.tracker:
                    self._yaw = self._smooth_angle(self._yaw, self.tracker.yaw())
                    self._pitch = self._smooth_angle(self._pitch, self.tracker.pitch())
                    self._roll = self._smooth_angle(self._roll, self.tracker.roll())
                    self.convolver.set_orientation(
                        self._yaw,
                        self._pitch,
                        self._roll,
                    )
                time.sleep(0.01)

        self._thread = Thread(target=_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self.convolver:
            self.convolver.stop()
        if self.tracker:
            self.tracker.stop()
        if self._thread:
            self._thread.join()
            self._thread = None