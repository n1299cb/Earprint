# See NOTICE.md for license and attribution details.

"""Interactive wizard for capturing impulse responses.

This module provides a console-based workflow for recording a set of
impulse responses for a given speaker layout. It can also be imported
and reused in a GUI context by supplying custom prompt and message
callbacks.
"""

import os
import argparse
import json
from typing import Any, Callable, Optional

from generate_layout import select_layout, init_layout
from constants import SPEAKER_NAMES, SMPTE_ORDER
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

def get_output_channels_for_group(speakers: list[str], speaker_channel_map: Optional[dict[str, int]] = None) -> list[int]:
    """Map speaker names to their channel indices.
    
    Args:
        speakers: List of speaker names (e.g., ["FL", "FR"] or ["FC"])
        speaker_channel_map: Optional user-defined mapping (e.g., {"FL": 0, "FR": 1, "FC": 2, "BL": 3, "BR": 4})
    
    Returns:
        List of channel indices
    """
    # Priority 1: Use user's custom mapping if provided
    if speaker_channel_map is not None:
        channels = []
        for speaker in speakers:
            if speaker in speaker_channel_map:
                channels.append(speaker_channel_map[speaker])
            else:
                print(f"⚠️ Speaker {speaker} not in user mapping, using SMPTE default")
                channels.append(_get_smpte_channel(speaker))
        return sorted(channels)
    
    # Priority 2: Use SMPTE default mapping
    channels = []
    for speaker in speakers:
        channels.append(_get_smpte_channel(speaker))
    return sorted(list(set(channels)))  # Remove duplicates and sort


def _get_smpte_channel(speaker: str) -> int:
    """Get SMPTE standard channel for a speaker."""
    mapping = {
        "FL": 0, "FR": 1, "FC": 2, "LFE": 3,
        "SL": 4, "SR": 5, "BL": 6, "BR": 7,
        "WL": 8, "WR": 9,
        "TFL": 10, "TFR": 11, "TML": 12, "TMR": 13,
        "TBL": 14, "TBR": 15,
    }
    return mapping.get(speaker, 0)


def run_capture(
    layout_name: str,
    groups: list[list[str]],
    out_dir: str,
    stereo_sweep: str = DEFAULT_STEREO_SWEEP,
    mono_sweep: str = DEFAULT_MONO_SWEEP,
    prompt_fn: Callable[[str], Any] = input,
    message_fn: Callable[[str], Any] = print,
    progress_fn: Optional[Callable[[float, float], None]] = None,
    auto_start: bool = False,
    speaker_channel_map: Optional[dict[str, int]] = None,
    **rec_kwargs: Any,
) -> None:
    """Run interactive capture for each speaker group.

    ``prompt_fn`` is used to pause between recordings, while ``message_fn`` is
    used to display progress messages. ``progress_fn`` receives progress updates
    for GUI display. All callbacks default to console implementations so the
    function can be reused in a GUI context by supplying custom callbacks.
    
    When ``auto_start`` is True, prompts are skipped and recordings start
    immediately - useful for GUI integration.
    """

    message_fn(f"\nRecording layout '{layout_name}' into {out_dir}\n")
    os.makedirs(out_dir, exist_ok=True)

    # Validate devices before starting to prevent PortAudio crashes
    try:
        import sounddevice as sd
        input_dev = rec_kwargs.get('input_device')
        output_dev = rec_kwargs.get('output_device')
        
        # Get device info
        if input_dev is None:
            input_device_info = sd.query_devices(sd.default.device[0], 'input')
        else:
            try:
                input_device_info = sd.query_devices(input_dev, 'input')
            except Exception:
                # Try as device name
                devices = sd.query_devices()
                input_device_info = None
                for idx, dev in enumerate(devices):
                    if dev['name'] == input_dev or str(idx) == str(input_dev):
                        if dev['max_input_channels'] > 0:
                            input_device_info = dev
                            break
                if input_device_info is None:
                    message_fn(f"⚠️  Could not find input device: {input_dev}")
                    return
        
        if output_dev is not None:
            try:
                output_device_info = sd.query_devices(output_dev, 'output')
            except Exception:
                devices = sd.query_devices()
                output_device_info = None
                for idx, dev in enumerate(devices):
                    if dev['name'] == output_dev or str(idx) == str(output_dev):
                        if dev['max_output_channels'] > 0:
                            output_device_info = dev
                            break
                if output_device_info is None:
                    message_fn(f"⚠️  Could not find output device: {output_dev}")
                    return
        
        # Check if input device supports stereo (2 channels) for binaural recording
        max_input_channels = input_device_info['max_input_channels']
        if max_input_channels < 2:
            error_msg = (
                f"\n⚠️  ERROR: Input device '{input_device_info['name']}' only has {max_input_channels} channel(s).\n"
                f"\n"
                f"Binaural recording requires 2 input channels (left and right ear microphones).\n"
                f"Your current device is MONO (1 channel).\n"
                f"\n"
                f"Please select a STEREO (2-channel) input device in the Earprint app settings.\n"
            )
            message_fn(error_msg)
            return
        
        message_fn(f"✓ Input device: {input_device_info['name']} ({max_input_channels} channels)")
        
    except Exception as exc:
        message_fn(f"⚠️  Device validation failed: {exc}")
        import traceback
        traceback.print_exc()
        return

    # Headphone recording - always 2 channels for binaural microphones
    if not auto_start:
        prompt_fn("Insert binaural microphones and wear headphones.\n" "Press Enter to record headphone response...")
    else:
        message_fn("Starting headphone response recording...")
    
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

    # Speaker group recordings
    for group in groups:
        filename = ",".join(group) + ".wav"
        sweep = stereo_sweep if len(group) > 1 else mono_sweep
        channels = 2
    
        if not auto_start:
            prompt = f"\nPosition for {filename} and press Enter to start recording..."
            prompt_fn(prompt)
        else:
            message_fn(f"\nRecording {filename}...")
    
        try:
            output_channels = get_output_channels_for_group(group, speaker_channel_map)  # ← Pass the map
            recorder.play_and_record(
                play=sweep,
                record=os.path.join(out_dir, filename),
                channels=channels,
                output_channels=output_channels,
                progress_callback=progress_fn,
                **rec_kwargs,
            )
        except Exception as exc:
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
    parser.add_argument(
        "--auto-start",
        action="store_true",
        help="Skip interactive prompts and start recordings immediately (for GUI use)",
    )
    parser.add_argument(
        "--channel_map",
        type=str,
        default=None,
        help='Channel mapping as JSON string (e.g., \'{"FL":0,"FR":1,"FC":2,"BL":3,"BR":4}\')'
    )
    parser.add_argument(
        "--input_channels",
        type=str,
        default=None,
        help="Comma-separated input channel indices for mic capture routing (e.g., '0,1')",
    )
    args = parser.parse_args()

    # Parse channel map from JSON
    speaker_channel_map = None
    if args.channel_map:
        try:
            speaker_channel_map = json.loads(args.channel_map)
            print(f"📍 Using custom channel mapping: {speaker_channel_map}")
        except json.JSONDecodeError:
            print(f"⚠️ Invalid channel map JSON: {args.channel_map}")
            return

    input_channels = None
    if args.input_channels:
        try:
            input_channels = [int(x.strip()) for x in args.input_channels.split(",")]
        except ValueError:
            print(f"⚠️ Invalid input_channels: {args.input_channels}")
            return

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
        auto_start=args.auto_start,
        speaker_channel_map=speaker_channel_map,
        input_channels=input_channels,
    )


if __name__ == "__main__":
    main()
