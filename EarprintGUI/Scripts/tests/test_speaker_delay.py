import builtins
import json
from speaker_delay import interactive_speaker_delays, load_delays
from constants import SPEAKER_NAMES


def test_interactive_speaker_delays(monkeypatch):
    inputs = [''] * (len(SPEAKER_NAMES) * 2)
    it = iter(inputs)
    monkeypatch.setattr(builtins, 'input', lambda _: next(it))
    monkeypatch.setattr(builtins, 'print', lambda *a, **k: None)

    delays = interactive_speaker_delays()

    assert set(delays.keys()) == set(SPEAKER_NAMES)
    assert min(delays.values()) == 0
    assert all(v == 0 for v in delays.values())


def test_load_delays_json(tmp_path):
    file = tmp_path / 'delays.json'
    with open(file, 'w', encoding='utf-8') as f:
        json.dump({'FL': 5, 'FR': 10, 'UNKNOWN': 1}, f)

    delays = load_delays(str(file))
    assert delays['FL'] == 0.005
    assert delays['FR'] == 0.01
    assert 'UNKNOWN' not in delays


def test_load_delays_csv(tmp_path):
    file = tmp_path / 'delays.csv'
    file.write_text('speaker,delay_ms\nFL,2\nFR,2\n')
    delays = load_delays(str(file))
    assert delays['FL'] == 0.002
    assert delays['FR'] == 0.002