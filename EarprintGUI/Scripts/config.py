# See NOTICE.md for license and attribution details.

from dataclasses import dataclass


@dataclass
class ProcessingConfig:
    """Feature flags controlling processing behaviour."""

    apply_diffuse_field_compensation: bool = False
    apply_headphone_eq: bool = True
    apply_x_curve_compensation: bool = False
    x_curve_type: str = "minus3db_oct"
    apply_room_correction: bool = False
    preserve_room_response: bool = True

    def update(self, **kwargs):
        for key, value in kwargs.items():
            if hasattr(self, key):
                setattr(self, key, value)


settings = ProcessingConfig()
