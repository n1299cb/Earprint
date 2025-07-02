# See NOTICE.md for license and attribution details.

"""Interactive wizard for capturing impulse responses.

This module provides a console-based workflow for recording a set of
impulse responses for a given speaker layout. It can also be imported
and reused in a GUI context by supplying custom prompt and message
callbacks.
"""

import os
import argparse
from typing import Any, Callable, Optional

from generate_layout import select_layout, init_layout
import recorder

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_STEREO_SWEEP = os.path.join(
    BASE_DIR,
    "data",
    "sweep-seg-FL,FR-stereo-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav",
)
DEFAULT_MONO_SWEEP = os.path.join(
    BASE_DIR,
    "data",
    "sweep-seg-FL-mono-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav",
)


def run_capture(
    layout_name: str,
    groups: list[list[str]],
    out_dir: str,
    stereo_sweep: str = DEFAULT_STEREO_SWEEP,
    mono_sweep: str = DEFAULT_MONO_SWEEP,
    prompt_fn: Callable[[str], Any] = input,
    message_fn: Callable[[str], Any] = print,
    progress_fn: Optional[Callable[[float, float], None]] = None,
    **rec_kwargs: Any,
) -> None:
    """Run interactive capture for each speaker group.

    ``prompt_fn`` is used to pause between recordings, while ``message_fn`` is
    used to display progress messages. ``progress_fn`` receives progress updates
    for GUI display. All callbacks default to console implementations so the
    function can be reused in a GUI context by supplying custom callbacks.
    """

    message_fn(f"\nRecording layout '{layout_name}' into {out_dir}\n")
    os.makedirs(out_dir, exist_ok=True)

    prompt_fn("Insert binaural microphones and wear headphones.\n" "Press Enter to record headphone response...")
    try:
        recorder.play_and_record(
            play=stereo_sweep,
            record=os.path.join(out_dir, "headphones.wav"),
            channels=2,
            progress_callback=progress_fn,
            **rec_kwargs,
        )
    except Exception as exc:  # pragma: no cover - depends on sounddevice
        message_fn(f"\n⚠️  Recording failed: {exc}")
        return

    for group in groups:
        filename = ",".join(group) + ".wav"
        sweep = stereo_sweep if len(group) > 1 else mono_sweep
        channels = len(group)
        prompt = f"\nPosition for {filename} and press Enter to start recording..."
        prompt_fn(prompt)
        try:
            recorder.play_and_record(
                play=sweep,
                record=os.path.join(out_dir, filename),
                channels=channels,
                progress_callback=progress_fn,
                **rec_kwargs,
            )
        except Exception as exc:  # pragma: no cover - depends on sounddevice
            message_fn(f"\n⚠️  Recording failed: {exc}")
            return

    message_fn("\n✅ Capture completed.")


def main() -> None:
    """Entry point for command-line execution."""

    parser = argparse.ArgumentParser(description="Step-by-step HRIR capture wizard")
    parser.add_argument("--layout", help="Layout name to use")
    parser.add_argument("--dir", default="data/test_capture", help="Target directory")
    parser.add_argument("--stereo_sweep", default=DEFAULT_STEREO_SWEEP, help="Stereo sweep file")
    parser.add_argument("--mono_sweep", default=DEFAULT_MONO_SWEEP, help="Mono sweep file")
    parser.add_argument(
        "--input_device",
        type=str,
        default=None,
        help="Input device name or number",
    )
    parser.add_argument(
        "--output_device",
        type=str,
        default=None,
        help="Output device name or number",
    )
    parser.add_argument("--host_api", type=str, default=None, help="Preferred host API")
    parser.add_argument(
        "--print_progress",
        action="store_true",
        help="Print recording progress updates for GUI integration",
    )
    args = parser.parse_args()

    progress_fn: Optional[Callable[[float, float], None]]
    if args.print_progress:

        def progress_fn(progress: float, remaining: float) -> None:
            print(f"PROGRESS {progress:.3f} {remaining:.3f}", flush=True)

    else:
        progress_fn = None

    layout_name, groups = select_layout(args.layout)
    init_layout(layout_name, groups, args.dir)

    run_capture(
        layout_name,
        groups,
        args.dir,
        stereo_sweep=args.stereo_sweep,
        mono_sweep=args.mono_sweep,
        input_device=args.input_device,
        output_device=args.output_device,
        host_api=args.host_api,
        progress_fn=progress_fn,
    )


if __name__ == "__main__":
    main()
