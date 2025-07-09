#!/usr/bin/env python3
"""
Export frequency response data from audio files to CSV format.

This script extracts frequency response data from various audio measurements
and exports them as CSV files for visualization and analysis.
"""

import os
import sys
import argparse
import csv
import numpy as np
from typing import Optional, Dict, Any

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from impulse_response_estimator import ImpulseResponseEstimator
from hrir import HRIR
from utils import read_wav


def export_headphone_response(estimator: ImpulseResponseEstimator,
                            measurement_dir: str,
                            output_dir: str) -> Dict[str, str]:
    """
    Export headphone frequency response to CSV files.
    
    Args:
        estimator: ImpulseResponseEstimator instance
        measurement_dir: Directory containing headphones.wav
        output_dir: Directory to save CSV files
        
    Returns:
        Dictionary mapping description to CSV file path
    """
    exported_files = {}
    headphones_path = os.path.join(measurement_dir, "headphones.wav")
    
    if not os.path.exists(headphones_path):
        print(f"Warning: {headphones_path} not found")
        return exported_files
    
    try:
        # Load headphone recording
        hp_irs = HRIR(estimator)
        hp_irs.open_recording(headphones_path, speakers=["FL", "FR"])
        
        # Get frequency responses
        left_fr = hp_irs.irs["FL"]["left"].frequency_response()
        right_fr = hp_irs.irs["FR"]["right"].frequency_response()
        
        # Center and smooth
        left_gain = left_fr.center([100, 10000])
        right_fr.raw += left_gain
        
        # Export raw headphone response
        raw_csv_path = os.path.join(output_dir, "headphones-raw.csv")
        with open(raw_csv_path, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(["frequency", "left_db", "right_db", "left_right_diff"])
            
            for freq, left_val, right_val in zip(left_fr.frequency, left_fr.raw, right_fr.raw):
                diff = left_val - right_val
                writer.writerow([freq, left_val, right_val, diff])
        
        exported_files["Raw Headphone Response"] = raw_csv_path
        
        # Smooth responses for easier visualization
        left_fr.smoothen_fractional_octave(window_size=1/3, treble_f_lower=20000, treble_f_upper=23999)
        right_fr.smoothen_fractional_octave(window_size=1/3, treble_f_lower=20000, treble_f_upper=23999)
        
        # Export smoothed headphone response
        smooth_csv_path = os.path.join(output_dir, "headphones-smoothed.csv")
        with open(smooth_csv_path, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(["frequency", "left_db", "right_db", "left_right_diff"])
            
            for freq, left_val, right_val in zip(left_fr.frequency, left_fr.smoothed, right_fr.smoothed):
                diff = left_val - right_val
                writer.writerow([freq, left_val, right_val, diff])
        
        exported_files["Smoothed Headphone Response"] = smooth_csv_path
        
        print(f"Exported headphone frequency response to {len(exported_files)} CSV files")
        
    except Exception as e:
        print(f"Error exporting headphone response: {e}")
    
    return exported_files


def export_hrir_response(estimator: ImpulseResponseEstimator,
                        measurement_dir: str,
                        output_dir: str) -> Dict[str, str]:
    """
    Export HRIR frequency response to CSV files.
    
    Args:
        estimator: ImpulseResponseEstimator instance
        measurement_dir: Directory containing measurement files
        output_dir: Directory to save CSV files
        
    Returns:
        Dictionary mapping description to CSV file path
    """
    exported_files = {}
    
    # Look for common HRIR file names
    hrir_candidates = [
        "hrir.wav",
        "responses.wav",
        "FL,FR.wav",
        "binaural.wav"
    ]
    
    hrir_path = None
    for candidate in hrir_candidates:
        candidate_path = os.path.join(measurement_dir, candidate)
        if os.path.exists(candidate_path):
            hrir_path = candidate_path
            break
    
    if not hrir_path:
        print("Warning: No HRIR file found")
        return exported_files
    
    try:
        # Load HRIR
        hrir = HRIR(estimator)
        
        # Determine speakers from filename or use defaults
        filename = os.path.basename(hrir_path)
        if "," in filename:
            speakers = filename.replace(".wav", "").split(",")
        else:
            speakers = ["FL", "FR"]  # Default
        
        hrir.open_recording(hrir_path, speakers=speakers)
        
        # Export frequency response for each speaker-ear combination
        all_responses = []
        headers = ["frequency"]
        
        for speaker in speakers:
            if speaker in hrir.irs:
                for side in ["left", "right"]:
                    if side in hrir.irs[speaker]:
                        ir = hrir.irs[speaker][side]
                        fr = ir.frequency_response()
                        fr.smoothen_fractional_octave(window_size=1/3)
                        
                        # Add to combined export
                        all_responses.append(fr.smoothed)
                        headers.append(f"{speaker}_{side}")
        
        if all_responses:
            # Export combined HRIR response
            combined_csv_path = os.path.join(output_dir, "hrir-response.csv")
            with open(combined_csv_path, 'w', newline='') as csvfile:
                writer = csv.writer(csvfile)
                writer.writerow(headers)
                
                # Use frequency from first response
                frequency = hrir.irs[speakers[0]]["left"].frequency_response().frequency
                
                for i, freq in enumerate(frequency):
                    row = [freq]
                    for response in all_responses:
                        if i < len(response):
                            row.append(response[i])
                        else:
                            row.append(0)  # Pad if needed
                    writer.writerow(row)
            
            exported_files["HRIR Response"] = combined_csv_path
            print(f"Exported HRIR frequency response with {len(headers)-1} channels")
    
    except Exception as e:
        print(f"Error exporting HRIR response: {e}")
    
    return exported_files


def export_room_response(measurement_dir: str, output_dir: str) -> Dict[str, str]:
    """
    Export room measurement data to CSV.
    
    Args:
        measurement_dir: Directory containing room measurement files
        output_dir: Directory to save CSV files
        
    Returns:
        Dictionary mapping description to CSV file path
    """
    exported_files = {}
    
    # Look for room measurement files
    room_files = [
        "room.wav",
        "room-response.wav",
        "room-measurements.wav"
    ]
    
    for room_file in room_files:
        room_path = os.path.join(measurement_dir, room_file)
        if os.path.exists(room_path):
            # For now, just note that room file exists
            # Full room response processing would require more complex logic
            exported_files[f"Room File Found"] = room_path
            print(f"Found room measurement file: {room_file}")
    
    return exported_files


def export_all_responses(measurement_dir: str,
                        test_signal: Optional[str] = None,
                        output_dir: Optional[str] = None) -> Dict[str, str]:
    """
    Export all available frequency response data to CSV files.
    
    Args:
        measurement_dir: Directory containing measurement files
        test_signal: Path to test signal file (optional)
        output_dir: Directory to save CSV files (defaults to measurement_dir/plots)
        
    Returns:
        Dictionary mapping description to CSV file path
    """
    if output_dir is None:
        output_dir = os.path.join(measurement_dir, "plots")
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Open impulse response estimator
    try:
        estimator = open_impulse_response_estimator(measurement_dir, test_signal)
    except Exception as e:
        print(f"Error creating impulse response estimator: {e}")
        return {}
    
    all_exports = {}
    
    # Export headphone response
    headphone_exports = export_headphone_response(estimator, measurement_dir, output_dir)
    all_exports.update(headphone_exports)
    
    # Export HRIR response
    hrir_exports = export_hrir_response(estimator, measurement_dir, output_dir)
    all_exports.update(hrir_exports)
    
    # Export room response
    room_exports = export_room_response(measurement_dir, output_dir)
    all_exports.update(room_exports)
    
    # Create summary file
    summary_path = os.path.join(output_dir, "export_summary.txt")
    with open(summary_path, 'w') as f:
        f.write("Earprint CSV Export Summary\n")
        f.write("=" * 30 + "\n\n")
        f.write(f"Source Directory: {measurement_dir}\n")
        f.write(f"Output Directory: {output_dir}\n")
        f.write(f"Exported Files: {len(all_exports)}\n\n")
        
        for description, filepath in all_exports.items():
            f.write(f"{description}: {os.path.basename(filepath)}\n")
    
    all_exports["Export Summary"] = summary_path
    
    return all_exports


def open_impulse_response_estimator(dir_path: str,
                                  file_path: Optional[str] = None,
                                  fs: int = 48000) -> ImpulseResponseEstimator:
    """
    Open impulse response estimator from directory.
    
    Args:
        dir_path: Path to measurement directory
        file_path: Explicit path to test signal (optional)
        fs: Sample rate for estimator
        
    Returns:
        ImpulseResponseEstimator instance
    """
    if file_path is None:
        # Look for test signal files
        test_candidates = ["test.pkl", "test.wav"]
        for candidate in test_candidates:
            candidate_path = os.path.join(dir_path, candidate)
            if os.path.exists(candidate_path):
                file_path = candidate_path
                break
    
    if file_path and file_path.endswith('.pkl'):
        return ImpulseResponseEstimator.from_pickle(file_path)
    elif file_path and file_path.endswith('.wav'):
        return ImpulseResponseEstimator.from_wav(file_path)
    else:
        return ImpulseResponseEstimator(fs=fs)


def main():
    """Command line interface for CSV export."""
    parser = argparse.ArgumentParser(description="Export Earprint frequency response data to CSV")
    parser.add_argument("--measurement_dir", "-d", required=True,
                       help="Directory containing measurement files")
    parser.add_argument("--test_signal", "-t",
                       help="Path to test signal file")
    parser.add_argument("--output_dir", "-o",
                       help="Output directory for CSV files (default: measurement_dir/plots)")
    parser.add_argument("--headphones_only", action="store_true",
                       help="Export only headphone response data")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.measurement_dir):
        print(f"Error: Measurement directory '{args.measurement_dir}' does not exist")
        return 1
    
    try:
        if args.headphones_only:
            estimator = open_impulse_response_estimator(args.measurement_dir, args.test_signal)
            output_dir = args.output_dir or os.path.join(args.measurement_dir, "plots")
            os.makedirs(output_dir, exist_ok=True)
            exports = export_headphone_response(estimator, args.measurement_dir, output_dir)
        else:
            exports = export_all_responses(args.measurement_dir, args.test_signal, args.output_dir)
        
        print(f"\nExport completed successfully!")
        print(f"Total files exported: {len(exports)}")
        for description, filepath in exports.items():
            print(f"  {description}: {filepath}")
            
        return 0
        
    except Exception as e:
        print(f"Error during export: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
