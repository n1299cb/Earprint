from __future__ import annotations

"""Simple OSC-based head tracking utilities."""

import threading
from typing import Callable, Optional

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import ThreadingOSCUDPServer


class HeadTracker:
    """Receive orientation updates via OSC."""

    def __init__(self, host: str = "0.0.0.0", port: int = 9000) -> None:
        self.host = host
        self.port = port
        self._yaw = 0.0
        self._pitch = 0.0
        self._roll = 0.0
        self._dispatcher = Dispatcher()
        self._dispatcher.map("/yaw", self._on_yaw)
        self._dispatcher.map("/pitch", self._on_pitch)
        self._dispatcher.map("/roll", self._on_roll)
        self._server = ThreadingOSCUDPServer((host, port), self._dispatcher)
        self._thread: Optional[threading.Thread] = None

    def _on_yaw(self, address: str, *args: float) -> None:
        if args:
            try:
                self._yaw = float(args[0])
            except (ValueError, TypeError):
                pass

    def _on_pitch(self, address: str, *args: float) -> None:
        if args:
            try:
                self._pitch = float(args[0])
            except (ValueError, TypeError):
                pass

    def _on_roll(self, address: str, *args: float) -> None:
        if args:
            try:
                self._roll = float(args[0])
            except (ValueError, TypeError):
                pass

    def start(self) -> None:
        if self._thread is None:
            self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
            self._thread.start()

    def stop(self) -> None:
        if self._thread is not None:
            self._server.shutdown()
            self._thread.join()
            self._thread = None

    def yaw(self) -> float:
        return self._yaw

    def pitch(self) -> float:
        return self._pitch

    def roll(self) -> float:
        return self._roll