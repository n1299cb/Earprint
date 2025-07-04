from capture_wizard import run_capture


def test_run_capture_handles_errors(monkeypatch, tmp_path):
    called = {"msg": []}
    def fake_play_and_record(**kwargs):
        raise RuntimeError("boom")
    monkeypatch.setattr("recorder.play_and_record", fake_play_and_record)
    def message_fn(msg):
        called["msg"].append(msg)
    run_capture("1.0", [["FL"]], str(tmp_path), message_fn=message_fn, prompt_fn=lambda x: None)
    assert any("boom" in m for m in called["msg"])  # error was reported