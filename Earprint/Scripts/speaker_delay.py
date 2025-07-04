from typing import Dict
import json
import csv
import os

from constants import SPEAKER_NAMES
from utils import versus_distance


def interactive_speaker_delays(default_distance: float = 3.0, default_angle: float = 0.0) -> Dict[str, float]:
    """Prompt for angle and distance per speaker and return delay table.

    The delay for the nearest speaker is normalised to zero.
    """
    print("Enter angle and distance for each speaker (press Enter for defaults).")
    delays = {}
    for sp in SPEAKER_NAMES:
        angle_str = input(f"{sp} angle [{default_angle} deg]: ")
        dist_str = input(f"{sp} distance [{default_distance} m]: ")
        angle = float(angle_str) if angle_str.strip() else default_angle
        distance = float(dist_str) if dist_str.strip() else default_distance
        _, delay, _ = versus_distance(angle=abs(angle), distance=distance, ear='primary')
        delays[sp] = delay

    min_delay = min(delays.values())
    for sp in delays:
        delays[sp] -= min_delay

    return delays


def load_delays(path: str) -> Dict[str, float]:
    """Load speaker delays from JSON or CSV file.

    Values are expected in milliseconds and are converted to seconds.
    Unknown speaker names are ignored.
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(path)

    delays_ms = {}
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError('JSON must contain an object mapping speaker names to delay')
        for name, value in data.items():
            if name.upper() in SPEAKER_NAMES:
                delays_ms[name.upper()] = float(value)
    except json.JSONDecodeError:
        with open(path, 'r', encoding='utf-8') as fh:
            reader = csv.reader(fh)
            rows = list(reader)
        for row in rows:
            if not row:
                continue
            name = row[0].strip().upper()
            if name not in SPEAKER_NAMES:
                continue
            try:
                value = float(row[1])
            except (IndexError, ValueError):
                continue
            delays_ms[name] = value

    return {k: v / 1000 for k, v in delays_ms.items()}