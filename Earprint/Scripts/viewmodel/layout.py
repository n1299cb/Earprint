from typing import Optional, List, Dict, Tuple
import json
import math
import os

from utils import versus_distance

from generate_layout import select_layout, init_layout, verify_layout


class LayoutViewModel:
    """ViewModel wrapping layout generation utilities."""

    def select_layout(self, name: Optional[str]) -> tuple[str, List[List[str]]]:
        return select_layout(name)

    def init_layout(self, name: str, groups: List[List[str]], out_dir: str) -> None:
        init_layout(name, groups, out_dir)

    def verify_layout(self, name: str, groups: List[List[str]], out_dir: str) -> None:
        verify_layout(name, groups, out_dir)

    # --- New helper methods ---
    def serialize_positions(
        self, positions: Dict[str, Tuple[float, float]], scale: float = 50.0
    ) -> List[Dict[str, float]]:
        """Convert scene coordinates to azimuth and distance."""
        data = []
        for name, (x, y) in positions.items():
            az = math.degrees(math.atan2(y, x))
            dist = math.hypot(x, y) / scale
            data.append({"name": name, "az": az, "dist": dist})
        return data

    def save_positions(
        self, positions: Dict[str, Tuple[float, float]], path: str, scale: float = 50.0
    ) -> List[Dict[str, float]]:
        """Serialize and persist speaker positions to ``path``."""
        data = self.serialize_positions(positions, scale=scale)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
        return data

    def distances_to_delays(self, placements: List[Dict[str, float]]) -> Dict[str, float]:
        """Calculate delay table from placement data."""
        delays = {}
        for entry in placements:
            _, delay, _ = versus_distance(angle=abs(entry["az"]), distance=entry["dist"], ear="primary")
            delays[entry["name"]] = delay
        if delays:
            min_delay = min(delays.values())
            for k in delays:
                delays[k] -= min_delay
        return delays

    def delays_from_positions(self, positions_file: str, delay_file: str) -> Dict[str, float]:
        """Load placement JSON, compute delays and save them."""
        with open(positions_file, "r", encoding="utf-8") as fh:
            placements = json.load(fh)
        delays = self.distances_to_delays(placements)
        os.makedirs(os.path.dirname(delay_file), exist_ok=True)
        with open(delay_file, "w", encoding="utf-8") as fh:
            json.dump({k: v * 1000 for k, v in delays.items()}, fh, indent=2)
        return delays