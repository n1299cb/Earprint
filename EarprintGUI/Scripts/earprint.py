# See NOTICE.md for license and attribution details.

import os
import re
import copy
from scipy.signal import butter, lfilter
import argparse
from tabulate import tabulate
from datetime import datetime
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from autoeq.frequency_response import FrequencyResponse
from impulse_response_estimator import ImpulseResponseEstimator
from hrir import HRIR
from room_correction import room_correction
from utils import sync_axes, save_fig_as_png
from constants import (
    SPEAKER_NAMES,
    SPEAKER_LIST_PATTERN,
    HESUVI_TRACK_ORDER,
)
from config import settings
from compensation import diffuse_field_compensation, apply_x_curve as apply_x_curve_filter
from constants import X_CURVE_DEFAULT_TYPE, X_CURVE_TYPES


def main(
    dir_path=None,
    test_signal=None,
    room_target=None,
    room_mic_calibration=None,
    fs=None,
    plot=False,
    channel_balance=None,
    decay=None,
    target_level=None,
    fr_combination_method="average",
    specific_limit=20000,
    generic_limit=1000,
    bass_boost_gain=0.0,
    bass_boost_fc=105,
    bass_boost_q=0.76,
    tilt=0.0,
    do_room_correction=True,
    do_headphone_compensation=True,
    do_diffuse_field_compensation=settings.apply_diffuse_field_compensation,
    head_ms=1,
    jamesdsp=False,
    hangloose=False,
    do_equalization=True,
    apply_x_curve=False,
    remove_x_curve=False,
    x_curve_in_capture=False,
    x_curve_type=X_CURVE_DEFAULT_TYPE,
    interactive_delays=False,
    delay_file=None,
):
    """"""
    if dir_path is None or not os.path.isdir(dir_path):
        raise NotADirectoryError(f'Given dir path "{dir_path}"" is not a directory.')

    # Dir path as absolute
    dir_path = os.path.abspath(dir_path)

    # Sample Rate Setup
    if fs is None:
        # Auto-detect fs from any HRIR recording
        for file in os.listdir(dir_path):
            if file.lower().endswith(".wav"):
                from utils import read_wav

                detected_fs, _ = read_wav(os.path.join(dir_path, file))
                fs = detected_fs
                print(f"[Auto FS] Using sample rate {fs} Hz from {file}")
                break
        if fs is None:
            raise ValueError("No WAV files found to auto-detect sample rate.")

    # Impulse response estimator
    print("Creating impulse response estimator...")
    estimator = open_impulse_response_estimator(dir_path, file_path=test_signal)

    if delay_file:
        from speaker_delay import load_delays
        from constants import SPEAKER_DELAYS

        SPEAKER_DELAYS.update(load_delays(delay_file))
    elif interactive_delays:
        from speaker_delay import interactive_speaker_delays
        from constants import SPEAKER_DELAYS

        SPEAKER_DELAYS.update(interactive_speaker_delays())

    # Room correction frequency responses
    room_frs = None
    if do_room_correction:
        print("Running room correction...")
        _, room_frs = room_correction(
            estimator,
            dir_path,
            target=room_target,
            mic_calibration=room_mic_calibration,
            fr_combination_method=fr_combination_method,
            specific_limit=specific_limit,
            generic_limit=generic_limit,
            plot=plot,
        )

    # Headphone compensation frequency responses
    hp_left, hp_right = None, None
    if do_headphone_compensation:
        print("Running headphone compensation...")
        hp_left, hp_right = headphone_compensation(estimator, dir_path)

    # Equalization
    eq_left, eq_right = None, None
    if do_equalization:
        print("Creating headphone equalization...")
        eq_left, eq_right = equalization(estimator, dir_path)

    # Bass boost and tilt
    print("Creating frequency response target...")
    target = create_target(estimator, bass_boost_gain, bass_boost_fc, bass_boost_q, tilt)

    # HRIR measurements
    print("Opening binaural measurements...")
    hrir = open_binaural_measurements(estimator, dir_path)

    # Diffuse Field Compensation Logic
    diffuse_field_compensation(hrir, enabled=do_diffuse_field_compensation)
    if apply_x_curve and not x_curve_in_capture:
        apply_x_curve_filter(hrir, curve_type=x_curve_type)
    if remove_x_curve and x_curve_in_capture:
        apply_x_curve_filter(hrir, inverse=True, curve_type=x_curve_type)

    readme = write_readme(os.path.join(dir_path, "README.md"), hrir, fs)

    if plot:
        # Plot graphs pre processing
        os.makedirs(os.path.join(dir_path, "plots", "pre"), exist_ok=True)
        print("Plotting BRIR graphs before processing...")
        hrir.plot(dir_path=os.path.join(dir_path, "plots", "pre"))

    # Crop noise and harmonics from the beginning
    print("Cropping impulse responses...")
    hrir.crop_heads(head_ms=head_ms)
    hrir.align_ipsilateral_all(
        speaker_pairs=[
            ("FL", "FR"),
            ("SL", "SR"),
            ("BL", "BR"),
            ("TFL", "TFR"),
            ("TSL", "TSR"),
            ("TBL", "TBR"),
            ("FC", "FC"),
            ("WL", "WR"),
        ],
        segment_ms=30,
    )
    hrir.crop_tails()

    # Write intermediate responses for debugging
    hrir.write_wav(os.path.join(dir_path, "responses.wav"))

    # Equalize all
    if do_headphone_compensation or do_room_correction or do_equalization:
        print("Equalizing...")
        for speaker, pair in hrir.irs.items():
            for side, ir in pair.items():
                fr = FrequencyResponse(
                    name=f"{speaker}-{side} eq",
                    frequency=FrequencyResponse.generate_frequencies(f_step=1.01, f_min=10, f_max=estimator.fs / 2),
                    raw=0,
                    error=0,
                )

                if room_frs is not None and speaker in room_frs and side in room_frs[speaker]:
                    # Room correction
                    fr.error += room_frs[speaker][side].error

                hp_eq = hp_left if side == "left" else hp_right
                if hp_eq is not None:
                    # Headphone compensation
                    fr.error += hp_eq.error

                eq = eq_left if side == "left" else eq_right
                if isinstance(eq, FrequencyResponse):
                    # Equalization
                    fr.error += eq.error

                # Remove bass and tilt target from the error
                fr.error -= target.raw

                # Smoothen and equalize
                fr.smoothen_heavy_light()
                fr.equalize(max_gain=40, treble_f_lower=10000, treble_f_upper=estimator.fs / 2)

                # Create FIR filter and equalize
                fir = fr.minimum_phase_impulse_response(fs=estimator.fs, normalize=False, f_res=5)
                ir.equalize(fir)

    # Adjust decay time
    if decay:
        print("Adjusting decay time...")
        for speaker, pair in hrir.irs.items():
            for side, ir in pair.items():
                if speaker in decay:
                    ir.adjust_decay(decay[speaker])

    # Correct channel balance
    if channel_balance is not None:
        print("Correcting channel balance...")
        hrir.correct_channel_balance(channel_balance)

    # Normalize gain
    print("Normalizing gain...")
    hrir.normalize(peak_target=None if target_level is not None else -0.1, avg_target=target_level)

    if plot:
        print("Plotting BRIR graphs after processing...")
        # Convolve test signal, re-plot waveform and spectrogram
        for speaker, pair in hrir.irs.items():
            for side, ir in pair.items():
                ir.recording = ir.convolve(estimator.test_signal)
        # Plot post processing
        hrir.plot(os.path.join(dir_path, "plots", "post"))

    # Plot results, always
    print("Plotting results...")
    hrir.plot_result(os.path.join(dir_path, "plots"))

    # Re-sample
    if fs is not None and fs != hrir.fs:
        print(f"Resampling BRIR to {fs} Hz")
        hrir.resample(fs)
        hrir.normalize(peak_target=None if target_level is not None else -0.1, avg_target=target_level)

    # Write multi-channel WAV file with standard track order
    print("Writing BRIRs...")
    hrir.write_wav(os.path.join(dir_path, "hrir.wav"))

    # Write multi-channel WAV file with HeSuVi track order
    hrir.write_wav(os.path.join(dir_path, "hesuvi.wav"), track_order=HESUVI_TRACK_ORDER)

    print(readme)

    if jamesdsp:
        print("Generating jamesdsp.wav (FL/FR only, normalized to FL/FR)...")
        import contextlib
        import io

        # Copy the entire HRIR and remove all channels except FL/FR
        dsp_hrir = copy.deepcopy(hrir)
        for sp in list(dsp_hrir.irs.keys()):
            if sp not in ["FL", "FR"]:
                del dsp_hrir.irs[sp]

        with contextlib.redirect_stdout(io.StringIO()):
            dsp_hrir.normalize(peak_target=None if target_level is not None else -0.1, avg_target=target_level)

        # Save channels in the order FL-L, FL-R, FR-L, FR-R
        jd_order = ["FL-left", "FL-right", "FR-left", "FR-right"]
        out_path = os.path.join(dir_path, "jamesdsp.wav")
        dsp_hrir.write_wav(out_path, track_order=jd_order)

    if hangloose:
        import numpy as np
        from scipy.io import wavfile

        output_dir = os.path.join(dir_path, "hangloose")
        os.makedirs(output_dir, exist_ok=True)

        # Maximum channel order based on hrir.wav
        full_order = [
            "FL",
            "FR",
            "FC",
            "LFE",
            "SL",
            "SR",
            "BL",
            "BR",
            "WL",
            "WR",
            "TFL",
            "TFR",
            "TSL",
            "TSR",
            "TBL",
            "TBR",
        ]
        processed = [sp for sp in full_order if sp in hrir.irs]

        # 1) Generate WAV for each speaker (including FC)
        for sp in processed:
            single = copy.deepcopy(hrir)
            for other in list(single.irs.keys()):
                if other != sp:
                    del single.irs[other]

            track_order = [f"{sp}-left", f"{sp}-right"]
            out_path = os.path.join(output_dir, f"{sp}.wav")
            single.write_wav(out_path, track_order=track_order)
            print(f"[Hangloose] Created: {out_path}")

        # 2) Read FL.wav and FR.wav to create LFEL.wav and LFER.wav
        for sp, out_name in [("FL", "LFEL.wav"), ("FR", "LFER.wav")]:
            src_path = os.path.join(output_dir, f"{sp}.wav")
            if not os.path.isfile(src_path):
                continue

            # 2.2) Design 120 Hz low-pass filter
            fs_read, data = wavfile.read(src_path)  # data.shape == (N, 2)

            # 2.2) 120 Hz 로우패스 필터 설계
            b, a = butter(4, 120 / (fs_read / 2), btype="low", analog=False)
            gain_lin = 10 ** (10 / 20)  # +10 dB

            # 2.3) Filter left and right channels and apply gain
            filtered_l = lfilter(b, a, data[:, 0]) * gain_lin
            filtered_r = lfilter(b, a, data[:, 1]) * gain_lin

            # 2.4) Save
            out_path = os.path.join(output_dir, out_name)
            lfe_data = np.vstack((filtered_l, filtered_r)).T.astype(data.dtype)
            wavfile.write(out_path, fs_read, lfe_data)
            print(f"[LFE conversion] Created: {out_path}")


def open_impulse_response_estimator(dir_path, file_path=None, fs=48000):
    """Opens impulse response estimator from a file

    Args:
        dir_path: Path to directory
        file_path: Explicitly given (if any) path to impulse response estimator Pickle or test signal WAV file
        fs: Sample rate of file

    Returns:
        ImpulseResponseEstimator instance
    """
    if file_path is None:
        # Test signal not explicitly given, try Pickle first then WAV
        if os.path.isfile(os.path.join(dir_path, "test.pkl")):
            file_path = os.path.join(dir_path, "test.pkl")
        elif os.path.isfile(os.path.join(dir_path, "test.wav")):
            file_path = os.path.join(dir_path, "test.wav")
    if isinstance(file_path, str) and re.match(r"^.+\.wav$", file_path, flags=re.IGNORECASE):
        # if re.match(r"^.+\.wav$", file_path, flags=re.IGNORECASE):
        # Test signal is WAV file
        estimator = ImpulseResponseEstimator.from_wav(file_path)
    elif isinstance(file_path, str) and re.match(r"^.+\.pkl$", file_path, flags=re.IGNORECASE):
        # elif re.match(r"^.+\.pkl$", file_path, flags=re.IGNORECASE):
        # Test signal is Pickle file
        estimator = ImpulseResponseEstimator.from_pickle(file_path)
    elif file_path is None:
        estimator = ImpulseResponseEstimator(fs=fs)
    else:
        raise TypeError(f'Unknown file extension for test signal "{file_path}"')
    return estimator


def equalization(estimator, dir_path):
    """Reads equalization FIR filter or CSV settings

    Args:
        estimator: ImpulseResponseEstimator
        dir_path: Path to directory

    Returns:
        - Left side FIR as Numpy array or FrequencyResponse or None
        - Right side FIR as Numpy array or FrequencyResponse or None
    """
    if os.path.isfile(os.path.join(dir_path, "eq.wav")):
        print("eq.wav is no longer supported, use eq.csv!")
    # Default for both sides
    eq_path = os.path.join(dir_path, "eq.csv")
    eq_fr = None
    if os.path.isfile(eq_path):
        eq_fr = FrequencyResponse.read_from_csv(eq_path)

    # Left
    left_path = os.path.join(dir_path, "eq-left.csv")
    left_fr = None
    if os.path.isfile(left_path):
        left_fr = FrequencyResponse.read_from_csv(left_path)
    elif eq_fr is not None:
        left_fr = eq_fr
    if left_fr is not None:
        left_fr.interpolate(f_step=1.01, f_min=10, f_max=estimator.fs / 2)

    # Right
    right_path = os.path.join(dir_path, "eq-right.csv")
    right_fr = None
    if os.path.isfile(right_path):
        right_fr = FrequencyResponse.read_from_csv(right_path)
    elif eq_fr is not None:
        right_fr = eq_fr
    if right_fr is not None and right_fr != left_fr:
        right_fr.interpolate(f_step=1.01, f_min=10, f_max=estimator.fs / 2)

    # Plot
    if left_fr is not None or right_fr is not None:
        if left_fr == right_fr:
            # Both are the same, plot only one graph
            fig, ax = plt.subplots()
            fig.set_size_inches(12, 9)
            left_fr.plot_graph(fig=fig, ax=ax, show=False)
        else:
            # Left and right are different, plot two graphs in the same figure
            fig, ax = plt.subplots(1, 2)
            fig.set_size_inches(22, 9)
            if left_fr is not None:
                left_fr.plot_graph(fig=fig, ax=ax[0], show=False)
            if right_fr is not None:
                right_fr.plot_graph(fig=fig, ax=ax[1], show=False)
        save_fig_as_png(os.path.join(dir_path, "plots", "eq.png"), fig)

    return left_fr, right_fr


def headphone_compensation(estimator, dir_path):
    """Equalizes HRIR tracks with headphone compensation measurement.

    Args:
        estimator: ImpulseResponseEstimator instance
        dir_path: Path to output directory

    Returns:
        None
    """
    # Read WAV file
    hp_irs = HRIR(estimator)
    hp_irs.open_recording(os.path.join(dir_path, "headphones.wav"), speakers=["FL", "FR"])
    hp_irs.write_wav(os.path.join(dir_path, "headphone-responses.wav"))

    # Frequency responses
    left = hp_irs.irs["FL"]["left"].frequency_response()
    right = hp_irs.irs["FR"]["right"].frequency_response()

    # Center by left channel
    gain = left.center([100, 10000])
    right.raw += gain

    # Compensate
    zero = FrequencyResponse(name="zero", frequency=left.frequency, raw=np.zeros(len(left.frequency)))
    left.compensate(zero, min_mean_error=False)
    right.compensate(zero, min_mean_error=False)

    # Headphone plots
    fig = plt.figure()
    gs = fig.add_gridspec(2, 3)
    fig.set_size_inches(22, 10)
    fig.suptitle("Headphones")

    # Left
    axl = fig.add_subplot(gs[0, 0])
    left.plot_graph(fig=fig, ax=axl, show=False)
    axl.set_title("Left")
    # Right
    axr = fig.add_subplot(gs[1, 0])
    right.plot_graph(fig=fig, ax=axr, show=False)
    axr.set_title("Right")
    # Sync axes
    sync_axes([axl, axr])

    # Combined
    _left = left.copy()
    _right = right.copy()
    gain_l = _left.center([100, 10000])
    gain_r = _right.center([100, 10000])
    ax = fig.add_subplot(gs[:, 1:])
    ax.plot(_left.frequency, _left.raw, linewidth=1, color="#1f77b4")
    ax.plot(_right.frequency, _right.raw, linewidth=1, color="#d62728")
    ax.plot(_left.frequency, _left.raw - _right.raw, linewidth=1, color="#680fb9")
    sl = np.logical_and(_left.frequency > 20, _left.frequency < 20000)
    stack = np.vstack([_left.raw[sl], _right.raw[sl], _left.raw[sl] - _right.raw[sl]])
    ax.set_ylim([np.min(stack) * 1.1, np.max(stack) * 1.1])
    axl.set_ylim([np.min(stack) * 1.1, np.max(stack) * 1.1])
    axr.set_ylim([np.min(stack) * 1.1, np.max(stack) * 1.1])
    ax.set_title("Comparison")
    ax.legend([f"Left raw {gain_l:+.1f} dB", f"Right raw {gain_r:+.1f} dB", "Difference"], fontsize=8)
    ax.set_xlabel("Frequency (Hz)")
    ax.semilogx()
    ax.set_xlim([20, 20000])
    ax.set_ylabel("Amplitude (dBr)")
    ax.grid(True, which="major")
    ax.grid(True, which="minor")
    ax.xaxis.set_major_formatter(ticker.StrMethodFormatter("{x:.0f}"))

    # Save headphone plots
    file_path = os.path.join(dir_path, "plots", "headphones.png")
    os.makedirs(os.path.split(file_path)[0], exist_ok=True)
    save_fig_as_png(file_path, fig)
    plt.close(fig)

    return left, right


def create_target(estimator, bass_boost_gain, bass_boost_fc, bass_boost_q, tilt):
    """Creates target frequency response with bass boost, tilt and high pass at 20 Hz"""
    target = FrequencyResponse(
        name="bass_and_tilt",
        frequency=FrequencyResponse.generate_frequencies(f_min=10, f_max=estimator.fs / 2, f_step=1.01),
    )
    target.raw = target.create_target(
        bass_boost_gain=bass_boost_gain, bass_boost_fc=bass_boost_fc, bass_boost_q=bass_boost_q, tilt=tilt
    )
    high_pass = FrequencyResponse(
        name="high_pass", frequency=[10, 18, 19, 20, 21, 22, 20000], raw=[-80, -5, -1.6, -0.6, -0.2, 0, 0]
    )
    high_pass.interpolate(f_min=10, f_max=estimator.fs / 2, f_step=1.01)
    # target.raw += high_pass.raw
    return target


def open_binaural_measurements(estimator, dir_path):
    """Opens binaural measurement WAV files.

    Args:
        estimator: ImpulseResponseEstimator
        dir_path: Path to directory

    Returns:
        HRIR instance
    """
    hrir = HRIR(estimator)
    pattern = r"^{pattern}\.wav$".format(pattern=SPEAKER_LIST_PATTERN)  # FL,FR.wav
    for file_name in [f for f in os.listdir(dir_path) if re.match(pattern, f)]:
        # Read the speaker names from the file name into a list
        speakers = re.search(SPEAKER_LIST_PATTERN, file_name)[0].split(",")
        # Form absolute path
        file_path = os.path.join(dir_path, file_name)
        # Print Sample Rate of Estimator
        print(f"Loading {file_path}, Estimator fs: {estimator.fs}")
        # Open the file and add tracks to HRIR
        hrir.open_recording(file_path, speakers=speakers)
    if len(hrir.irs) == 0:
        raise ValueError("No HRIR recordings found in the directory.")
    return hrir


def write_readme(file_path, hrir, fs):
    """Writes info and stats to readme file.

    Args:
        file_path: Path to readme file
        hrir: HRIR instance
        fs: Output sampling rate

    Returns:
        Readme string
    """
    if fs is None:
        fs = hrir.fs

    rt_name = "Reverb"
    rt = None
    table = []
    speaker_names = sorted(hrir.irs.keys(), key=lambda x: SPEAKER_NAMES.index(x))
    for speaker in speaker_names:
        pair = hrir.irs[speaker]
        itd = np.abs(pair["right"].peak_index() - pair["left"].peak_index()) / hrir.fs * 1e6
        for side, ir in pair.items():
            # Zero for the first ear
            _itd = itd if side == "left" and speaker[1] == "R" or side == "right" and speaker[1] == "L" else 0.0
            # Use the largest decay time parameter available
            peak_ind, knee_point_ind, noise_floor, window_size = ir.decay_params()
            edt, rt20, rt30, rt60 = ir.decay_times(peak_ind, knee_point_ind, noise_floor, window_size)
            if rt60 is not None:
                rt_name = "RT60"
                rt = rt60
            elif rt30 is not None:
                rt_name = "RT30"
                rt = rt30
            elif rt20 is not None:
                rt_name = "RT20"
                rt = rt20
            elif edt is not None:
                rt_name = "EDT"
                rt = edt
            table.append(
                [
                    speaker,
                    side,
                    f"{noise_floor:.1f} dB",
                    f"{_itd:.1f} us",
                    f"{(knee_point_ind - peak_ind) / ir.fs * 1000:.1f} ms",
                    f"{rt * 1000:.1f} ms" if rt is not None else "-",
                ]
            )
    table_str = tabulate(table, headers=["Speaker", "Side", "PNR", "ITD", "Length", rt_name], tablefmt="github")

    # --- Calculating reflected sound energy (20–50 ms, 50–150 ms) per main ear channel ---
    def frame(ms: float) -> int:
        return int(ms * 1e-3 * fs)

    def to_db(E: float, E0: float) -> float:
        return 10 * np.log10(E / (E0 + 1e-20))

    energy_lines = ["\n**Reflected Sound Energy Compared to Direct Sound (per Channel, dB):**"]
    for speaker, channels in hrir.irs.items():
        # If the speaker name ends with L, only the left channel is used, otherwise only the right channel is used.
        main_side = "left" if speaker.endswith("L") else "right"
        data = channels[main_side].data
        peak = np.argmax(np.abs(data))
        E0 = np.sum(data[peak : peak + frame(5)] ** 2)
        E_early = np.sum(data[peak + frame(20) : peak + frame(50)] ** 2)
        E_mid = np.sum(data[peak + frame(50) : peak + frame(150)] ** 2)
        energy_lines.append(
            f"- {speaker} ({main_side}): "
            f"Early (20–50 ms) {to_db(E_early, E0):.2f} dB, "
            f"Mid (50–150 ms) {to_db(E_mid,   E0):.2f} dB"
        )
    energy_str = "\n" + "\n".join(energy_lines)

    s = f"""# HRIR

    **Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}  
    **Input sampling rate:** {hrir.fs} Hz  
    **Output sampling rate:** {fs} Hz  

    {table_str}
    {energy_str}
    """
    s = re.sub("\n[ \t]+", "\n", s).strip()

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(s)

    return s


def create_cli():
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument(
        "--c", type=float, default=1, help="Retain headroom in milliseconds before the impulse peak. Default is 1 ms."
    )
    arg_parser.add_argument(
        "--jamesdsp", action="store_true", help="Generate an additional jamesdsp.wav containing only FL/FR IRs."
    )
    arg_parser.add_argument(
        "--hangloose", action="store_true", help="Create Hangloose files per channel (left/right WAV per speaker)"
    )
    arg_parser.add_argument("--dir_path", type=str, required=True, help="Path to directory for recordings and outputs.")
    arg_parser.add_argument(
        "--test_signal",
        type=str,
        default=argparse.SUPPRESS,
        help="Path to sine sweep test signal or pickled impulse response estimator.",
    )
    arg_parser.add_argument(
        "--room_target", type=str, default=argparse.SUPPRESS, help="Path to room target response AutoEQ style CSV file."
    )
    arg_parser.add_argument(
        "--room_mic_calibration",
        type=str,
        default=argparse.SUPPRESS,
        help="Path to room measurement microphone calibration file.",
    )
    arg_parser.add_argument(
        "--no_room_correction", action="store_false", dest="do_room_correction", help="Skip room correction."
    )
    arg_parser.add_argument(
        "--no_headphone_compensation",
        action="store_false",
        dest="do_headphone_compensation",
        help="Skip headphone compensation.",
    )
    arg_parser.add_argument(
        "--diffuse_field_compensation",
        action="store_true",
        dest="do_diffuse_field_compensation",
        default=settings.apply_diffuse_field_compensation,
        help="Apply diffuse-field compensation to the HRIR.",
    )
    arg_parser.add_argument(
        "--no_equalization", action="store_false", dest="do_equalization", help="Skip equalization."
    )
    arg_parser.add_argument("--fs", type=int, default=argparse.SUPPRESS, help="Output sampling rate in Hertz.")
    arg_parser.add_argument("--plot", action="store_true", help="Plot graphs for debugging.")
    arg_parser.add_argument(
        "--channel_balance",
        type=str,
        default=argparse.SUPPRESS,
        help=(
            "Channel balance correction by equalizing left and right ear results to the same "
            'level or frequency response. "trend" equalizes right side by the difference trend '
            'of right and left side. "left" equalizes right side to left side fr, "right" '
            'equalizes left side to right side fr, "avg" equalizes both to the average fr, "min" '
            "equalizes both to the minimum of left and right side frs. Number values will boost "
            'or attenuate right side relative to left side by the number of dBs. "mids" is the '
            "same as the numerical values but guesses the value automatically from mid frequency "
            "levels."
        ),
    )
    arg_parser.add_argument(
        "--decay",
        type=str,
        default=argparse.SUPPRESS,
        help=(
            "Target decay time in milliseconds to reach -60 dB. When the natural decay time is "
            "longer than the target decay time, a downward slope will be applied to decay tail. "
            "Decay cannot be increased with this. By default no decay time adjustment is done. "
            "A comma separated list of channel name and  reverberation time pairs, separated by "
            "a colon. If only a single numeric value is given, it is used for all channels. When "
            "some channel names are give but not all, the missing channels are not affected. For "
            'example "--decay=300" or "--decay=FL:500,FC:100,FR:500,SR:700,BR:700,BL:700,SL:700" '
            'or "--decay=FC:100".'
        ),
    )
    arg_parser.add_argument(
        "--target_level",
        type=float,
        default=argparse.SUPPRESS,
        help="Target average gain level for left and right channels. This will sum together all "
        "left side impulse responses and right side impulse responses respectively and take "
        "the average gain from mid frequencies. The averaged level is then normalized to the "
        "given target level. This makes it possible to compare HRIRs with somewhat similar "
        "loudness levels. This should be negative in most cases to avoid clipping.",
    )
    arg_parser.add_argument(
        "--fr_combination_method",
        type=str,
        default="average",
        help=(
            "Method for combining frequency responses of generic room measurements if there are "
            "more than one tracks in the file. \"average\" will simply average the frequency"
            "responses. \"conservative\" will take the minimum absolute value for each frequency "
            "but only if the values in all the measurements are positive or negative at the same "
            "time."
        ),
    )
    arg_parser.add_argument(
        "--specific_limit",
        type=float,
        default=400,
        help=(
            "Upper limit for room equalization with speaker-ear specific room measurements. "
            "Equalization will drop down to 0 dB at this frequency in the leading octave. 0 "
            "disables limit."
        ),
    )
    arg_parser.add_argument(
        "--generic_limit",
        type=float,
        default=300,
        help=(
            "Upper limit for room equalization with generic room measurements. "
            "Equalization will drop down to 0 dB at this frequency in the leading octave. 0 "
            "disables limit."
        ),
    )
    arg_parser.add_argument(
        "--bass_boost",
        type=str,
        default=argparse.SUPPRESS,
        help=(
            "Bass boost shelf. Sub-bass frequencies will be boosted by this amount. Can be "
            "either a single value for a gain in dB or a comma separated list of three values for "
            "parameters of a low shelf filter, where the first is gain in dB, second is center "
            "frequency (Fc) in Hz and the last is quality (Q). When only a single value (gain) is "
            "given, default values for Fc and Q are used which are 105 Hz and 0.76, respectively. "
            'For example "--bass_boost=6" or "--bass_boost=6,150,0.69".'
        ),
    )
    arg_parser.add_argument(
        "--tilt",
        type=float,
        default=argparse.SUPPRESS,
        help="Target tilt in dB/octave. Positive value (upwards slope) will result in brighter "
        "frequency response and negative value (downwards slope) will result in darker "
        "frequency response. 1 dB/octave will produce nearly 10 dB difference in "
        "desired value between 20 Hz and 20 kHz. Tilt is applied with bass boost and both "
        "will affect the bass gain.",
    )
    arg_parser.add_argument("--apply_x_curve", action="store_true", help="Apply SMPTE X-Curve to the output HRIR.")
    arg_parser.add_argument("--remove_x_curve", action="store_true", help="Remove SMPTE X-Curve from the output HRIR.")
    arg_parser.add_argument("--x_curve_in_capture", action="store_true", help="Capture already includes X-Curve.")
    arg_parser.add_argument(
        "--x_curve_type",
        type=str,
        default=X_CURVE_DEFAULT_TYPE,
        choices=list(X_CURVE_TYPES.keys()),
        help="Which X-Curve profile to use.",
    )
    arg_parser.add_argument(
        "--delay-file", dest="delay_file", type=str, help="JSON or CSV file with speaker delays in milliseconds."
    )
    arg_parser.add_argument(
        "--interactive_delays", action="store_true", help="Prompt for speaker angles and distances to compute delays."
    )
    args = vars(arg_parser.parse_args())
    if "bass_boost" in args:
        bass_boost = args["bass_boost"].split(",")
        if len(bass_boost) == 1:
            args["bass_boost_gain"] = float(bass_boost[0])
            args["bass_boost_fc"] = 105
            args["bass_boost_q"] = 0.76
        elif len(bass_boost) == 3:
            args["bass_boost_gain"] = float(bass_boost[0])
            args["bass_boost_fc"] = float(bass_boost[1])
            args["bass_boost_q"] = float(bass_boost[2])
        else:
            raise ValueError('"--bass_boost" must have one value or three values separated by commas!')
        del args["bass_boost"]
    if "decay" in args:
        decay = dict()
        try:
            # Single float value
            decay = {ch: float(args["decay"]) / 1000 for ch in SPEAKER_NAMES}
        except ValueError:
            # Channels separated
            for ch_t in args["decay"].split(","):
                decay[ch_t.split(":")[0].upper()] = float(ch_t.split(":")[1]) / 1000
        args["decay"] = decay
    if "c" in args:
        args["head_ms"] = args["c"]
        del args["c"]
    return args


if __name__ == "__main__":
    main(**create_cli())
