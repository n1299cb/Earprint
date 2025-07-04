import os
import sys

# Allow importing modules from repository root
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

from constants import (
    SPEAKER_LAYOUTS,
    SPEAKER_LAYOUT_INDEXES,
    SMPTE_LAYOUT_INDEXES,
    SMPTE_ORDER,
    CHANNEL_LABELS,
    SPEAKER_NAMES,
)

EXPECTED_LAYOUTS = {
    "1.0": 1,
    "2.0": 2,
    "5.1": 5,
    "7.1": 7,
    "7.1.4": 11,
    "9.1.6": 15,
    "5.1.4": 9,
    "7.1.2": 9,
    "7.1.6": 13,
    "9.1.4": 13,
    "5.1.2": 7,
    "ambisonics": 4,
}


def test_layout_definitions_exist():
    for fmt, count in EXPECTED_LAYOUTS.items():
        assert fmt in SPEAKER_LAYOUTS, f"Missing layout {fmt}"
        # Flatten groups and count channels
        flat = [ch for group in SPEAKER_LAYOUTS[fmt] for ch in group]
        assert len(flat) == count
        # SMPTE index definitions should match
        assert fmt in SMPTE_LAYOUT_INDEXES
        # SMPTE layouts may include LFE which is not part of SPEAKER_LAYOUTS
        assert len(SMPTE_ORDER[fmt]) >= count


def test_channel_labels_consistency():
    for i, name in enumerate(SPEAKER_NAMES):
        assert CHANNEL_LABELS[i] == name


def test_mono_layout_first_channel():
    assert SPEAKER_LAYOUT_INDEXES["1.0"] == [(0,)]
    assert SMPTE_LAYOUT_INDEXES["1.0"] == [(0,)]