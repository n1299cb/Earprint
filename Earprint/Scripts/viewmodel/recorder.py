from typing import Any, Callable, List, Optional
import subprocess
import sys
import os

from models import RecorderSettings


class RecordingViewModel:
    """ViewModel handling recording commands."""

    def run_recorder(
        self,
        settings: RecorderSettings,
        progress_callback: Optional[Callable[[float, float], None]] = None,
    ) -> subprocess.CompletedProcess:
        """Run recorder with proper channel constraints."""
        
        # Determine if this is a room recording based on output file
        is_room_recording = settings.is_room_recording()
        
        # Determine proper channel count
        if is_room_recording:
            # Room recordings must be mono (1 channel)
            channels = 1
        else:
            # Measurement recordings use output channel count, default to 2 for binaural
            channels = len(settings.output_channels) if settings.output_channels else 2
        
        # For subprocess calls (when no progress callback)
        if progress_callback is None:
            record_path = settings.output_file or os.path.join(settings.measurement_dir, "recording.wav")
            args = [
                sys.executable,
                "recorder.py",
                "--play", settings.test_signal,
                "--record", record_path,
                "--output_device", settings.playback_device,
                "--input_device", settings.recording_device,
                "--channels", str(channels),
            ]
            
            # Add optional output file if different from record path
            if settings.output_file and settings.output_file != record_path:
                args.extend(["--output_file", settings.output_file])
            
            return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        else:
            # Direct function call with progress callback
            from recorder import play_and_record

            record_path = settings.output_file or os.path.join(settings.measurement_dir, "recording.wav")
            
            # Validate speaker layout if this is a measurement recording
            if not is_room_recording and settings.output_file:
                self._validate_speaker_layout_filename(settings.output_file, len(settings.output_channels or []))
            
            play_and_record(
                play=settings.test_signal,
                record=record_path,
                input_device=settings.recording_device,
                output_device=settings.playback_device,
                channels=channels,
                progress_callback=progress_callback,
            )
            return subprocess.CompletedProcess(args=[], returncode=0, stdout="", stderr="")

    def _validate_speaker_layout_filename(self, output_file: str, channel_count: int) -> None:
        """Validate that filename matches expected speaker layout."""
        filename = os.path.basename(output_file)
        if filename.endswith('.wav'):
            speaker_names = filename[:-4].split(',')
            if len(speaker_names) != channel_count:
                print(f"Warning: {len(speaker_names)} speaker labels in filename '{filename}', "
                      f"but {channel_count} output channels specified.")

    def run_capture_wizard(
        self,
        layout_name: str,
        layout_groups: List[List[str]],
        settings: RecorderSettings,
        prompt_fn: Optional[Callable[[str], Any]] = None,
        message_fn: Optional[Callable[[str], Any]] = None,
        progress_callback: Optional[Callable[[float, float], None]] = None,
    ) -> None:
        from capture_wizard import run_capture

        run_capture(
            layout_name,
            layout_groups,
            settings.measurement_dir,
            prompt_fn=prompt_fn,
            message_fn=message_fn,
            input_device=settings.recording_device,
            output_device=settings.playback_device,
            progress_fn=progress_callback,
        )
