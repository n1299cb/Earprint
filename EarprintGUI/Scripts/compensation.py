# See NOTICE.md for license and attribution details.

import numpy as np
from autoeq.frequency_response import FrequencyResponse
from constants import (
    X_CURVE_TYPES,
    X_CURVE_DEFAULT_TYPE,
)
from config import settings


def diffuse_field_compensation(hrir, enabled=settings.apply_diffuse_field_compensation):
    """Apply diffuse-field compensation to HRIR in-place."""
    if not enabled:
        return
 
    for pair in hrir.irs.values():
        for ir in pair.values():
            fr = ir.frequency_response()
            fr.diffuse_field_compensation()
            fir = fr.minimum_phase_impulse_response(fs=hrir.fs)
            ir.equalize(fir)


def apply_x_curve(hrir, inverse=False, curve_type=X_CURVE_DEFAULT_TYPE):
    """Apply or remove SMPTE X-Curve to HRIR.

    Parameters
    ----------
    hrir: HRIR
        Impulse responses to modify.
    inverse: bool
        If True, removes the curve instead of applying it.
    curve_type: str
        Which curve profile from :data:`constants.X_CURVE_TYPES` to use.
    """
    if not settings.apply_x_curve_compensation and not inverse:
        return

    if curve_type not in X_CURVE_TYPES:
        raise ValueError(f"Unknown X-Curve type: {curve_type}")

    curve = X_CURVE_TYPES[curve_type]
    ref_freq = curve["ref_frequency"]
    slope = curve["slope"]

    freqs = FrequencyResponse.generate_frequencies(f_min=10, f_max=hrir.fs / 2, f_step=1.01)
    gain = np.zeros_like(freqs)
    mask = freqs >= ref_freq
    gain[mask] = slope * np.log2(freqs[mask] / ref_freq)
    if inverse:
        gain = -gain
    fr = FrequencyResponse(name="x_curve", frequency=freqs, raw=gain)
    fir = fr.minimum_phase_impulse_response(fs=hrir.fs)
    for pair in hrir.irs.values():
        for ir in pair.values():
            ir.equalize(fir)