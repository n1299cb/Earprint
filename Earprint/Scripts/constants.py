# See NOTICE.md for license and attribution details.

"""Common constants used throughout the project."""

# -*- coding: utf-8 -*-

import json
import os
from typing import TypedDict, Dict, List, Tuple

from config import settings

PROJECT_ROOT = os.path.abspath(os.path.dirname(__file__))
DEFAULT_TEST_SIGNAL = os.path.join(
    PROJECT_ROOT,
    "data",
    "sweep-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav",
)
DEFAULT_MEASUREMENT_DIR = os.path.join(PROJECT_ROOT, "data", "demo")

SPEAKER_NAMES = [
    "FL",
    "FR",  # 0–1
    "FC",  # 2
    "LFE",  # 3
    "SL",
    "SR",  # 4–5 (Side surrounds)
    "BL",
    "BR",  # 6–7 (Back surrounds)
    "WL",
    "WR",  # 8–9 (Wide L/R)
    "TFL",
    "TFR",
    "TSL",
    "TSR",
    "TBL",
    "TBR",  # 10–15
    "W",
    "X",
    "Y",
    "Z",  # 16–19 Ambisonics channels
]

# Speaker layout indexes (without LFE channel for reference formats)
SPEAKER_LAYOUT_INDEXES: dict[str, list[tuple[int, ...]]] = {
    "1.0": [(0,)],  # Mono (front left)
    "2.0": [(0, 1)],  # Front Left, Front Right
    "5.1": [(0, 1), (2,), (6, 7)],  # 2.0 plus Center, Back Left and Back Right
    "7.1": [
        (0, 1),
        (2,),
        (4, 5),
        (6, 7),
    ],  # 5.1 plus Side Left, Side Right, then Back Left/Back Right
    "7.1.4": [(0, 1), (2,), (4, 5), (6, 7), (10, 11), (14, 15)],
    "9.1.6": [
        (0, 1),  # Front Left, Front Right
        (2,),  # Center
        (4, 5),  # Side Left, Side Right
        (6, 7),  # Back Left, Back Right
        (8, 9),  # Wide Left, Wide Right
        (10, 11),  # Top Front Left, Top Front Right
        (12, 13),  # Top Middle Left, Top Middle Right
        (14, 15),  # Top Back Left, Top Back Right
    ],
    "5.1.4": [
        (0, 1),  # Front Left, Front Right
        (2,),  # Center
        (6, 7),  # Back Left, Back Right
        (10, 11),  # Top Front Left, Top Front Right
        (14, 15),  # Top Back Left, Top Back Right
    ],
    "7.1.2": [
        (0, 1),  # Front Left, Front Right
        (2,),  # Center
        (4, 5),  # Side Left, Side Right
        (6, 7),  # Back Left, Back Right
        (10, 11),  # Top Front Left, Top Front Right
    ],
    "7.1.6": [
        (0, 1),  # Front Left, Front Right
        (2,),  # Center
        (4, 5),  # Side Left, Side Right
        (6, 7),  # Back Left, Back Right
        (10, 11),  # Top Front Left, Top Front Right
        (12, 13),  # Top Middle Left, Top Middle Right
        (14, 15),  # Top Back Left, Top Back Right
    ],
    "9.1.4": [
        (0, 1),  # Front Left, Front Right
        (2,),  # Center
        (4, 5),  # Side Left, Side Right
        (6, 7),  # Back Left, Back Right
        (8, 9),  # Wide Left, Wide Right
        (10, 11),  # Top Front Left, Top Front Right
        (14, 15),  # Top Back Left, Top Back Right
    ],
    "5.1.2": [
        (0, 1),  # Front Left, Front Right
        (2,),  # Center
        (6, 7),  # Back Left, Back Right
        (10, 11),  # Top Front Left, Top Front Right
    ],
    "ambisonics": [(16,), (17,), (18,), (19,)],
}
# Resolved layout mappings (label groups)

USER_LAYOUT_PRESETS_FILE = os.environ.get("EARPRINT_LAYOUT_PRESETS", "user_layouts.json")


def load_user_layout_presets(file_path: str = USER_LAYOUT_PRESETS_FILE) -> Dict[str, List[List[str]]]:
    """Load user-defined layouts from JSON file."""
    if not os.path.exists(file_path):
        return {}
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return {}
        return {k: v for k, v in data.items() if isinstance(v, list)}
    except (OSError, json.JSONDecodeError):
        return {}


def save_user_layout_preset(name: str, groups: list[list[str]], file_path: str = USER_LAYOUT_PRESETS_FILE) -> None:
    """Save layout preset to JSON file."""
    layouts = load_user_layout_presets(file_path)
    layouts[name] = groups
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(layouts, f, indent=2)


USER_SPEAKER_LAYOUTS = load_user_layout_presets()

SPEAKER_LAYOUTS: dict[str, list[list[str]]] = {
    name: [[SPEAKER_NAMES[i] for i in group] for group in groups] for name, groups in SPEAKER_LAYOUT_INDEXES.items()
}
SPEAKER_LAYOUTS.update(USER_SPEAKER_LAYOUTS)

# Convert user layout groups to index mappings using built-in speaker names
USER_LAYOUT_INDEXES: dict[str, list[tuple[int, ...]]] = {
    name: [tuple(SPEAKER_NAMES.index(ch) for ch in group) for group in groups]
    for name, groups in USER_SPEAKER_LAYOUTS.items()
    if all(ch in SPEAKER_NAMES for group in groups for ch in group)
}
SPEAKER_LAYOUT_INDEXES.update(USER_LAYOUT_INDEXES)


def register_user_layouts(layouts: dict[str, list[list[str]]]) -> None:
    """Register additional user layout presets at runtime."""
    for name, groups in layouts.items():
        SPEAKER_LAYOUTS[name] = groups
        SPEAKER_LAYOUT_INDEXES[name] = [
            tuple(SPEAKER_NAMES.index(ch) for ch in group)
            for group in groups
            if all(ch in SPEAKER_NAMES for ch in group)
        ]


def load_and_register_user_layouts(file_path: str) -> Dict[str, List[List[str]]]:
    """Load presets from ``file_path`` and register them."""
    layouts = load_user_layout_presets(file_path)
    register_user_layouts(layouts)
    return layouts


# Regex patterns and helpers
SPEAKER_PATTERN = f'({"|".join(SPEAKER_NAMES + ["X"])})'
SPEAKER_LIST_PATTERN = r"{speaker_pattern}+(,{speaker_pattern})*".format(speaker_pattern=SPEAKER_PATTERN)

SPEAKER_DELAYS = {_speaker: 0 for _speaker in SPEAKER_NAMES}


# Available X-Curve profiles with reference frequency and slope in dB/octave
X_CURVE_TYPES = {
    # Standard cinema X-Curve: ∼-3 dB/octave above 2 kHz
    "minus3db_oct": {"ref_frequency": 2000, "slope": -3.0},
    # Small room variant: ∼-1.5 dB/octave above 2 kHz
    "minus1p5db_oct": {"ref_frequency": 2000, "slope": -1.5},
}

# Default profile used when type is not specified
X_CURVE_DEFAULT_TYPE = "minus3db_oct"

# Reference frequency for X-Curve slope in Hz (for backward compatibility)
X_CURVE_REF_FREQUENCY = X_CURVE_TYPES[X_CURVE_DEFAULT_TYPE]["ref_frequency"]
# Slope of X-Curve in decibels per octave (for backward compatibility)
X_CURVE_SLOPE_DB_PER_OCTAVE = X_CURVE_TYPES[X_CURVE_DEFAULT_TYPE]["slope"]


# Each channel, left and right
IR_ORDER: list[str] = []
# SPL change relative to middle of the head - disable
IR_ROOM_SPL = {sp: {"left": 0.0, "right": 0.0} for sp in SPEAKER_NAMES}
COLORS = {
    "lightblue": "#7db4db",
    "blue": "#1f77b4",
    "pink": "#dd8081",
    "red": "#d62728",
    "lightpurple": "#ecdef9",
    "purple": "#680fb9",
    "green": "#2ca02c",
}

HESUVI_TRACK_ORDER = [
    "FL-left",
    "FL-right",
    "SL-left",
    "SL-right",
    "BL-left",
    "BL-right",
    "FC-left",
    "FR-right",
    "FR-left",
    "SR-right",
    "SR-left",
    "BR-right",
    "BR-left",
    "FC-right",
    "WL-left",
    "WL-right",
    "WR-left",
    "WR-right",
    "TFL-left",
    "TFL-right",
    "TFR-left",
    "TFR-right",
    "TSL-left",
    "TSL-right",
    "TSR-left",
    "TSR-right",
    "TBL-left",
    "TBL-right",
    "TBR-left",
    "TBR-right",
]

HEXADECAGONAL_TRACK_ORDER = [
    "FL-left",
    "FL-right",
    "FR-left",
    "FR-right",
    "FC-left",
    "FC-right",
    "LFE-left",
    "LFE-right",
    "BL-left",
    "BL-right",
    "BR-left",
    "BR-right",
    "SL-left",
    "SL-right",
    "SR-left",
    "SR-right",
    "WL-left",
    "WL-right",
    "WR-left",
    "WR-right",
    "TFL-left",
    "TFL-right",
    "TFR-left",
    "TFR-right",
    "TSL-left",
    "TSL-right",
    "TSR-left",
    "TSR-right",
    "TBL-left",
    "TBL-right",
    "TBR-left",
    "TBR-right",
]

# Map channel index to name using the default layout (first entry in SPEAKER_NAMES)
CHANNEL_LABELS = {i: name for i, name in enumerate(SPEAKER_NAMES)}
# Optional reverse lookup for GUI usage
CHANNEL_LABELS_REVERSE = {name: i for i, name in CHANNEL_LABELS.items()}
# Map layout name to flat list of speaker indices
FORMAT_PRESETS: dict[str, list[int]] = {name: [idx for group in groups for idx in group] for name, groups in SPEAKER_LAYOUT_INDEXES.items()}
# SMPTE layout index definitions per format
SMPTE_LAYOUT_INDEXES: dict[str, list[tuple[int, ...]]] = {
    "1.0": [(0,)],
    "2.0": [(0, 1)],
    "5.1": [(0, 1), (2,), (3,), (6, 7)],
    "7.1": [(0, 1), (2,), (3,), (4, 5), (6, 7)],
    "7.1.4": [(0, 1), (2,), (3,), (4, 5), (6, 7), (10, 11), (14, 15)],
    "9.1.6": [(0, 1), (2,), (3,), (4, 5), (6, 7), (8, 9), (10, 11), (12, 13), (14, 15)],
    "5.1.4": [(0, 1), (2,), (3,), (6, 7), (10, 11), (14, 15)],
    "7.1.2": [(0, 1), (2,), (3,), (4, 5), (6, 7), (10, 11)],
    "7.1.6": [(0, 1), (2,), (3,), (4, 5), (6, 7), (10, 11), (12, 13), (14, 15)],
    "9.1.4": [(0, 1), (2,), (3,), (4, 5), (6, 7), (8, 9), (10, 11), (14, 15)],
    "5.1.2": [(0, 1), (2,), (3,), (6, 7), (10, 11)],
    "ambisonics": [(16,), (17,), (18,), (19,)],
}
# Preset orders using SPEAKER_LAYOUT_INDEXES for SMPTE
# Flattened versions for GUI use
SMPTE_ORDER: dict[str, list[int]] = {fmt: [i for group in SMPTE_LAYOUT_INDEXES[fmt] for i in group] for fmt in SMPTE_LAYOUT_INDEXES}
