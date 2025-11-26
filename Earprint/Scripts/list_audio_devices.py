#!/usr/bin/env python3
"""List all available audio devices with their channel information."""

import sounddevice as sd


def list_devices():
    """List all audio devices with detailed channel information."""
    devices = sd.query_devices()
    
    print("\n" + "="*80)
    print("AVAILABLE AUDIO DEVICES")
    print("="*80 + "\n")
    
    # Input devices
    print("INPUT DEVICES (for recording):")
    print("-" * 80)
    input_count = 0
    for idx, dev in enumerate(devices):
        if dev['max_input_channels'] > 0:
            input_count += 1
            channels = dev['max_input_channels']
            channel_type = "STEREO ✓" if channels >= 2 else "MONO ✗"
            default_marker = " [DEFAULT]" if idx == sd.default.device[0] else ""
            
            print(f"{idx:2d}. {dev['name']}")
            print(f"    Channels: {channels} ({channel_type}){default_marker}")
            print(f"    Host API: {sd.query_hostapis(dev['hostapi'])['name']}")
            print(f"    Sample Rate: {dev['default_samplerate']:.0f} Hz")
            print()
    
    if input_count == 0:
        print("  No input devices found!\n")
    
    # Output devices
    print("\nOUTPUT DEVICES (for playback):")
    print("-" * 80)
    output_count = 0
    for idx, dev in enumerate(devices):
        if dev['max_output_channels'] > 0:
            output_count += 1
            channels = dev['max_output_channels']
            default_marker = " [DEFAULT]" if idx == sd.default.device[1] else ""
            
            print(f"{idx:2d}. {dev['name']}")
            print(f"    Channels: {channels}{default_marker}")
            print(f"    Host API: {sd.query_hostapis(dev['hostapi'])['name']}")
            print(f"    Sample Rate: {dev['default_samplerate']:.0f} Hz")
            print()
    
    if output_count == 0:
        print("  No output devices found!\n")
    
    print("="*80)
    print("\nREQUIREMENTS FOR EARPRINT:")
    print("  - Input device must have 2+ channels (STEREO) for binaural recording")
    print("  - Output device must match your speaker layout (2.0, 5.1, 7.1, etc.)")
    print("="*80 + "\n")


if __name__ == "__main__":
    try:
        list_devices()
    except Exception as e:
        print(f"\nError listing devices: {e}")
        import traceback
        traceback.print_exc()
