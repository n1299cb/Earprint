from dataclasses import dataclass
from typing import List, Optional


@dataclass
class RecorderSettings:
    measurement_dir: str
    test_signal: str
    playback_device: str
    recording_device: str
    output_channels: List[int]
    input_channels: List[int]
    output_file: str = ""
    
    def validate(self) -> List[str]:
        """Validate recorder settings and return list of errors."""
        errors = []
        
        if not self.measurement_dir:
            errors.append("measurement_dir is required")
        
        if not self.test_signal:
            errors.append("test_signal is required")
        
        if not self.playback_device:
            errors.append("playback_device is required")
        
        if not self.recording_device:
            errors.append("recording_device is required")
        
        # Validate channel constraints
        if self.is_room_recording():
            if len(self.input_channels) > 1:
                errors.append("Room recordings must use single input channel (mono)")
        
        return errors
    
    def is_room_recording(self) -> bool:
        """Check if this is a room recording based on output file."""
        if not self.output_file:
            return False
        filename = self.output_file.lower()
        return "room.wav" in filename or "room-" in filename
    
    def is_headphone_recording(self) -> bool:
        """Check if this is a headphone recording based on output file."""
        if not self.output_file:
            return False
        return "headphones.wav" in self.output_file.lower()
    
    def get_expected_input_channels(self) -> int:
        """Get expected number of input channels based on recording type."""
        if self.is_room_recording():
            return 1  # Room recordings are always mono
        elif self.is_headphone_recording():
            return 2  # Headphone recordings are always stereo (binaural)
        else:
            return 2  # Default to stereo for measurement recordings
