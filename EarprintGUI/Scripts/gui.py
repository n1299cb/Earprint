# See NOTICE.md for license and attribution details.

"""Graphical user interface for running Earprint workflows."""

import sys
import os
import PySide6
import sounddevice as sd
import soundfile as sf
import math
import numpy as np
import queue
import threading
import matplotlib
import json
from dataclasses import asdict
from typing import Optional
from pathlib import Path

if sys.platform == "darwin" and "QT_QPA_PLATFORM_PLUGIN_PATH" not in os.environ:
    plugin_dir = Path(PySide6.__file__).resolve().parent / "Qt" / "plugins"
    os.environ["QT_QPA_PLATFORM_PLUGIN_PATH"] = str(plugin_dir)
    print(f"Using Qt plugins path: {plugin_dir}")

matplotlib.use("QtAgg")
from PySide6.QtWidgets import (
    QSizePolicy,
    QApplication,
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QFileDialog,
    QComboBox,
    QLineEdit,
    QTabWidget,
    QMessageBox,
    QTextEdit,
    QCheckBox,
    QSlider,
    QDialog,
    QToolButton,
    QGraphicsView,
    QGraphicsScene,
    QGraphicsEllipseItem,
    QGraphicsTextItem,
    QProgressBar,
    QListWidget,
    QInputDialog,
    QGroupBox,
)
from PySide6.QtGui import (
    QShortcut,
    QKeySequence,
    QPixmap,
    QBrush,
    QPen,
    QColor,
    QPainter,
    QRadialGradient,
)
from PySide6.QtCore import Qt, QPointF, QTimer

from viewmodel.measurement_setup import MeasurementSetupViewModel
from viewmodel.processing import ProcessingViewModel
from viewmodel.recorder import RecordingViewModel
from models import ProcessingSettings, RecorderSettings
from constants import (
    FORMAT_PRESETS,
    SPEAKER_NAMES,
    X_CURVE_TYPES,
    X_CURVE_DEFAULT_TYPE,
    SPEAKER_LAYOUTS,
    DEFAULT_TEST_SIGNAL,
    DEFAULT_MEASUREMENT_DIR,
)
from viewmodel.layout import LayoutViewModel
from level_meter import LevelMonitor
import preset_manager
import user_profiles
import room_presets
from contextlib import redirect_stdout
import io
import datetime


class EarprintGUI(QMainWindow):
    """Main window providing access to recording and processing tools."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Earprint GUI")
        self.resize(700, 700)

        # ViewModels
        self.setup_vm = MeasurementSetupViewModel()
        self.processing_vm = ProcessingViewModel()
        self.recorder_vm = RecordingViewModel()
        self.layout_vm = LayoutViewModel()

        self.channel_mappings = {}

        # Default speaker layout
        self.selected_layout_name = next(iter(FORMAT_PRESETS))
        self.selected_layout = [SPEAKER_NAMES[i] for i in FORMAT_PRESETS[self.selected_layout_name]]

        self.tabs = QTabWidget()
        self.tab_order = []
        self.setCentralWidget(self.tabs)

        # self.create_headphone_eq_tab() called only once
        # Temporarily defer Setup tab creation
        # self.create_measurement_setup_tab()
        self.create_processing_options_tab()
        self.create_compensation_tab()
        self.create_room_response_tab()
        self.create_headphone_eq_tab()
        self.create_execution_tab()
        self.create_measurement_setup_tab()  # Measurement setup defines widgets used in later tabs
        self.create_profile_tab()
        self.create_visualization_tab()
        self.setup_shortcuts()
        self.run_startup_checks()

    def create_measurement_setup_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)
        layout.addWidget(
            QLabel(
                """
        In this tab, configure the test signal, measurement directory, and select
        playback and recording devices used for capturing impulse responses.
        """
            )
        )

        self.test_signal_path_var = QLineEdit()
        self.test_signal_path_var.setMaximumWidth(300)
        self.test_signal_path_var.setText(DEFAULT_TEST_SIGNAL)
        self.test_signal_path_var.setPlaceholderText("e.g., /path/to/test_signal.wav")
        browse_test = QPushButton("Browse")
        browse_test.setMaximumWidth(100)
        browse_test.clicked.connect(self.browse_test_signal)

        self.advanced_toggle = QToolButton()
        self.advanced_toggle.setText("Advanced")
        self.advanced_toggle.setCheckable(True)
        self.advanced_toggle.setArrowType(Qt.RightArrow)
        self.advanced_toggle.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.advanced_toggle.toggled.connect(self.toggle_advanced)

        self.advanced_frame = QWidget()
        adv_layout = QVBoxLayout(self.advanced_frame)
        adv_layout.setContentsMargins(0, 0, 0, 0)
        adv_layout.addLayout(
            self.labeled_row(
                "Select Test Signal File:",
                self.test_signal_path_var,
                browse_test,
            )
        )
        self.advanced_frame.setVisible(False)

        layout.addWidget(self.advanced_toggle)
        layout.addWidget(self.advanced_frame)

        self.measurement_dir_var = QLineEdit()
        self.measurement_dir_var.setMaximumWidth(300)
        self.measurement_dir_var.setText(DEFAULT_MEASUREMENT_DIR)
        self.measurement_dir_var.setPlaceholderText("e.g., /path/to/measurements/")
        browse_dir = QPushButton("Browse")
        browse_dir.setMaximumWidth(100)
        browse_dir.clicked.connect(self.browse_measurement_dir)
        layout.addLayout(
            self.labeled_row(
                "Select Measurement Directory:",
                self.measurement_dir_var,
                browse_dir,
            )
        )

        # Layout selection
        self.layout_var = QComboBox()
        self.layout_var.addItems(FORMAT_PRESETS.keys())
        self.layout_var.addItem("Custom...")
        self.layout_var.setCurrentText(self.selected_layout_name)
        self.layout_var.currentTextChanged.connect(self.handle_layout_change)
        layout.addLayout(self.labeled_row("Speaker Layout:", self.layout_var))

        save_layout_btn = QPushButton("Save Layout…")
        save_layout_btn.clicked.connect(self.save_layout_preset)
        layout.addWidget(save_layout_btn)

        import_layout_btn = QPushButton("Import Layout…")
        import_layout_btn.clicked.connect(self.import_layout_preset)
        layout.addWidget(import_layout_btn)

        self.playback_device_var = QComboBox()
        self.playback_device_var.setMaximumWidth(200)

        self.recording_device_var = QComboBox()
        self.recording_device_var.setMaximumWidth(200)
        self.load_device_options()

        layout.addLayout(self.labeled_row("Playback Device:", self.playback_device_var))
        layout.addLayout(self.labeled_row("Recording Device:", self.recording_device_var))

        map_btn = QPushButton("Map Channels")
        map_btn.clicked.connect(self.map_channels)
        layout.addWidget(map_btn)

        auto_map_btn = QPushButton("Auto Map")
        auto_map_btn.clicked.connect(self.auto_map_channels)
        layout.addWidget(auto_map_btn)

        wizard_btn = QPushButton("Layout Wizard")
        wizard_btn.clicked.connect(self.open_layout_wizard)
        layout.addWidget(wizard_btn)

        view_btn = QPushButton("View Layout")
        view_btn.clicked.connect(self.open_layout_viewer)
        layout.addWidget(view_btn)

        # Real-time input level monitor
        self.level_bar = QProgressBar()
        self.level_bar.setRange(0, 100)
        self.output_level_bar = QProgressBar()
        self.output_level_bar.setRange(0, 100)
        self.monitor_btn = QPushButton("Start Monitor")
        self.monitor_btn.setCheckable(True)
        self.monitor_btn.toggled.connect(self.toggle_monitor)
        layout.addLayout(self.labeled_row("Input Level:", self.level_bar, self.monitor_btn))
        layout.addLayout(self.labeled_row("Output Level:", self.output_level_bar))

        self.monitor_timer = QTimer()
        self.monitor_timer.timeout.connect(self.read_monitor_level)
        self.level_monitor = None
        self.monitor_thread = None
        self.output_monitor = None
        self.output_thread = None

        # Validation button
        self.test_signal_path_var.textChanged.connect(self.validate_measurement_setup)
        self.measurement_dir_var.textChanged.connect(self.validate_measurement_setup)
        self.measurement_dir_var.textChanged.connect(self.load_plot_files)

        self.tabs.addTab(tab, "Setup")

    def validate_measurement_setup(self):
        test_signal = self.test_signal_path_var.text()
        measurement_dir = self.measurement_dir_var.text()
        # Validate using ViewModel and apply simple error highlighting
        errors = self.setup_vm.validate_paths(test_signal, measurement_dir)

        self.test_signal_path_var.setStyleSheet(
            "border: 2px solid red;" if "test_signal" in errors else "border: 2px solid green;"
        )
        self.measurement_dir_var.setStyleSheet(
            "border: 2px solid red;" if "measurement_dir" in errors else "border: 2px solid green;"
        )

        if errors:
            messages = []
            if "test_signal" in errors:
                messages.append("Test signal file path is invalid or does not exist. ")
            if "measurement_dir" in errors:
                messages.append("Measurement directory path is invalid or does not exist.")
            QMessageBox.critical(self, "Validation Failed", "".join(messages))
        else:
            QMessageBox.information(self, "Validation Passed", "All paths are valid.")

    def create_compensation_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)
        summary = QLabel(
            """
        This tab allows you to configure compensation settings that correct headphone coloration
        and apply pre-measured or theoretical frequency response adjustments. Useful for ensuring
        consistent playback across different headphone types or compensation targets.
        """
        )
        summary.setWordWrap(True)
        summary.setSizePolicy(summary.sizePolicy().horizontalPolicy(), QSizePolicy.Minimum)
        layout.addWidget(summary)
        # Compensation Tab: Apply headphone and response compensation

        self.enable_compensation_var = QCheckBox("Enable Compensation")
        layout.addWidget(self.enable_compensation_var)

        self.compensation_type_var = QComboBox()
        self.compensation_type_var.addItems(["Diffuse-field", "Free-field", "Custom"])
        self.compensation_type_var.currentTextChanged.connect(self.update_compensation_file_state)
        layout.addLayout(self.labeled_row("Compensation Type:", self.compensation_type_var))

        self.compensation_file_path_var = QLineEdit()
        browse_comp = QPushButton("Browse")
        browse_comp.clicked.connect(self.browse_compensation_file)
        self.compensation_file_path_var = QLineEdit()
        self.compensation_custom_widget = QWidget()
        custom_layout = QHBoxLayout(self.compensation_custom_widget)
        custom_layout.addWidget(QLabel("Custom Compensation File:"))
        custom_layout.addWidget(self.compensation_file_path_var)
        custom_layout.addWidget(browse_comp)
        layout.addWidget(self.compensation_custom_widget)
        self.update_compensation_file_state()

        self.headphone_eq_toggle = QCheckBox("Enable Headphone EQ")
        layout.addWidget(self.headphone_eq_toggle)

        self.diffuse_field_toggle = QCheckBox("Apply Diffuse-Field Compensation")
        layout.addWidget(self.diffuse_field_toggle)

        self.headphone_file_path_var = QLineEdit()
        self.headphone_file_path_var.setPlaceholderText("e.g., /path/to/headphones.wav")
        browse_hp = QPushButton("Browse")
        browse_hp.clicked.connect(self.browse_headphone_file)
        layout.addLayout(
            self.labeled_row(
                "Headphone EQ File (headphones.wav):",
                self.headphone_file_path_var,
                browse_hp,
            )
        )

        self.x_curve_action_var = QComboBox()
        self.x_curve_action_var.addItems(["None", "Apply X-Curve", "Remove X-Curve"])
        layout.addLayout(self.labeled_row("X-Curve Action:", self.x_curve_action_var))

        self.x_curve_type_var = QComboBox()
        self.x_curve_type_var.addItems(list(X_CURVE_TYPES.keys()))
        idx = self.x_curve_type_var.findText(X_CURVE_DEFAULT_TYPE)
        if idx >= 0:
            self.x_curve_type_var.setCurrentIndex(idx)
        layout.addLayout(self.labeled_row("X-Curve Type:", self.x_curve_type_var))

        self.x_curve_in_capture_var = QCheckBox("Capture Includes X-Curve")
        layout.addWidget(self.x_curve_in_capture_var)

        self.tabs.addTab(tab, "Compensation")

    def create_room_response_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)
        layout.addWidget(
            QLabel(
                (
                    "Record a room response for use with room correction processing. "
                    "This requires a calibrated microphone and the same test signal used for IR capture."
                )
            )
        )

        steps = QLabel(
            """
        Steps:
        1. Position your calibrated microphone at the Main Listening Position.
        2. Ensure the test signal and measurement directory are set correctly.
        3. Click below to record the room response.
        """
        )
        steps.setWordWrap(True)
        layout.addWidget(steps)

        note = QLabel(
            """
        Note: If you have a microphone calibration file, it will be applied during the processing step,
        not during this recording. You can specify it in the Processing Options tab.
        """
        )
        note.setWordWrap(True)
        layout.addWidget(note)

        self.room_response_button = QPushButton("Record Room Response")
        self.room_response_button.setMaximumWidth(200)
        self.room_response_button.clicked.connect(self.launch_room_response_recorder)
        centered_button_layout = QHBoxLayout()
        centered_button_layout.addStretch()
        centered_button_layout.addWidget(self.room_response_button)
        centered_button_layout.addStretch()
        layout.addLayout(centered_button_layout)

        self.add_room_presets_section(layout)

        self.tabs.insertTab(1, tab, "Room Response")

    def create_headphone_eq_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)
        layout.addWidget(
            QLabel(
                """
        Headphone EQ allows you to capture the frequency response of your headphones
        using a binaural microphone setup. This is optional but recommended for
        more accurate BRIR processing.
        """
            )
        )

        steps = QLabel(
            """
        Steps:
        1. Insert your binaural microphones.
        2. Wear your headphones.
        3. Play the test signal and record using the button below.
        """
        )
        steps.setWordWrap(True)
        layout.addWidget(steps)

        self.hp_recorder_button2 = QPushButton("Record Headphone EQ")
        self.hp_recorder_button2.setMaximumWidth(200)
        self.hp_recorder_button2.clicked.connect(self.launch_headphone_recorder)
        centered_button_layout = QHBoxLayout()
        centered_button_layout.addStretch()
        centered_button_layout.addWidget(self.hp_recorder_button2)
        centered_button_layout.addStretch()
        layout.addLayout(centered_button_layout)

        self.tabs.insertTab(0, tab, "Headphone EQ")

    def create_execution_tab(self):
        # Create Execution tab first and bring it to focus
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)
        layout.addWidget(
            QLabel(
                """
        Use this tab to launch the recorder or run the processing pipeline.
        Review logs, clear or save output, and troubleshoot from here.
        """
            )
        )
        # Execution Tab: Run processing and launch recorders

        self.run_button = QPushButton("Run Processing")
        self.run_button.clicked.connect(self.run_processing)
        layout.addWidget(self.run_button)

        self.recorder_button = QPushButton("Launch Recorder")
        self.recorder_button.clicked.connect(self.launch_recorder)
        layout.addWidget(self.recorder_button)

        self.capture_wizard_button = QPushButton("Capture Wizard")
        self.capture_wizard_button.clicked.connect(self.launch_capture_wizard)
        layout.addWidget(self.capture_wizard_button)

        self.hp_recorder_button = QPushButton("Record Headphone EQ")
        self.hp_recorder_button.clicked.connect(self.launch_headphone_recorder)
        # Removed from Execution tab to move into Headphone EQ tab

        export_btn = QPushButton("Export Hesuvi Preset")
        export_btn.clicked.connect(self.export_hesuvi_preset)
        layout.addWidget(export_btn)
       
        # Recording progress bar and remaining time
        self.record_progress = QProgressBar()
        self.record_progress.setRange(0, 100)
        self.record_progress.hide()
        self.remaining_label = QLabel("")
        layout.addWidget(self.record_progress)
        layout.addWidget(self.remaining_label)

        self.output_text = QTextEdit()
        self.output_text.setReadOnly(True)
        log_controls = QHBoxLayout()
        clear_log_btn = QPushButton("Clear Log")
        save_log_btn = QPushButton("Save Log")
        clear_log_btn.clicked.connect(lambda: self.output_text.clear())
        save_log_btn.clicked.connect(self.save_log)
        self.log_file_check = QCheckBox("Auto Log to File")
        self.log_file_path = QLineEdit()
        self.log_file_path.setPlaceholderText("/path/to/log.txt")
        browse_log = QPushButton("Browse")
        browse_log.clicked.connect(self.browse_log_file)
        log_controls.addWidget(clear_log_btn)
        log_controls.addWidget(save_log_btn)
        log_controls.addWidget(self.log_file_check)
        log_controls.addWidget(self.log_file_path)
        log_controls.addWidget(browse_log)
        layout.addLayout(log_controls)
        layout.addWidget(self.output_text)
        self.startup_status_label = QLabel("Startup Check: Pending")
        layout.addWidget(self.startup_status_label)

        self.tabs.addTab(tab, "Execution")
        self.tabs.setTabText(self.tabs.indexOf(tab), "★ Execution")
        self.tabs.setCurrentWidget(tab)

    def run_processing(self):
        # Delegate path validation to the ViewModel
        errors = self.setup_vm.validate_paths(self.test_signal_path_var.text(), self.measurement_dir_var.text())
        if errors:
            if "measurement_dir" in errors:
                QMessageBox.critical(
                    self,
                    "Error",
                    "Please ensure the measurement directory is valid before processing.",
                )
            if "test_signal" in errors:
                QMessageBox.critical(
                    self,
                    "Error",
                    "Please ensure the test signal file is valid before processing.",
                )
            return

        settings = self.gather_processing_settings()
        try:
            result = self.processing_vm.run(settings)
            cmd = " ".join(result.args)
            self.append_output(f"Running: {cmd}")
            if result.stdout:
                self.append_output(result.stdout, color="green")
            if result.stderr:
                self.append_output(result.stderr, color="red")
        except (FileNotFoundError, OSError) as e:
            self.append_output(f"Error: {str(e)}")

    def launch_room_response_recorder(self):
        errors = self.setup_vm.validate_paths(self.test_signal_path_var.text(), self.measurement_dir_var.text())
        if errors:
            QMessageBox.critical(
                self,
                "Error",
                "Please ensure the test signal and measurement directory are valid before recording.",
            )
            return
        try:
            settings = RecorderSettings(
                measurement_dir=self.measurement_dir_var.text(),
                test_signal=self.test_signal_path_var.text(),
                playback_device=self.playback_device_var.currentText().split(":")[0],
                recording_device=self.recording_device_var.currentText().split(":")[0],
                output_channels=self.channel_mappings.get("output_channels", []),
                input_channels=self.channel_mappings.get("input_channels", []),
                output_file=os.path.join(self.measurement_dir_var.text(), "room.wav"),
            )
            result = self.recorder_vm.run_recorder(settings, progress_callback=self.update_record_progress)
            if result.stdout:
                self.append_output(result.stdout, color="green")
            if result.stderr:
                self.append_output(result.stderr, color="red")
        except (FileNotFoundError, OSError) as e:
            QMessageBox.critical(self, "Room Response Recorder Error", str(e))

    def launch_headphone_recorder(self):
        errors = self.setup_vm.validate_paths(self.test_signal_path_var.text(), self.measurement_dir_var.text())
        if errors:
            QMessageBox.critical(
                self,
                "Error",
                "Please ensure the test signal and measurement directory are valid before recording.",
            )
            return
        try:
            settings = RecorderSettings(
                measurement_dir=self.measurement_dir_var.text(),
                test_signal=self.test_signal_path_var.text(),
                playback_device=self.playback_device_var.currentText().split(":")[0],
                recording_device=self.recording_device_var.currentText().split(":")[0],
                output_channels=self.channel_mappings.get("output_channels", []),
                input_channels=self.channel_mappings.get("input_channels", []),
                output_file=os.path.join(self.measurement_dir_var.text(), "headphones.wav"),
            )
            result = self.recorder_vm.run_recorder(settings, progress_callback=self.update_record_progress)
            if result.stdout:
                self.append_output(result.stdout, color="green")
            if result.stderr:
                self.append_output(result.stderr, color="red")
        except (FileNotFoundError, OSError) as e:
            QMessageBox.critical(self, "Headphone Recorder Error", str(e))

    def launch_recorder(self):
        errors = self.setup_vm.validate_paths(self.test_signal_path_var.text(), self.measurement_dir_var.text())
        if errors:
            QMessageBox.critical(
                self,
                "Error",
                "Please ensure the test signal and measurement directory are valid before recording.",
            )
            return
        try:
            settings = RecorderSettings(
                measurement_dir=self.measurement_dir_var.text(),
                test_signal=self.test_signal_path_var.text(),
                playback_device=self.playback_device_var.currentText().split(":")[0],
                recording_device=self.recording_device_var.currentText().split(":")[0],
                output_channels=self.channel_mappings.get("output_channels", []),
                input_channels=self.channel_mappings.get("input_channels", []),
            )
            result = self.recorder_vm.run_recorder(settings, progress_callback=self.update_record_progress)
            if result.stdout:
                self.append_output(result.stdout, color="green")
            if result.stderr:
                self.append_output(result.stderr, color="red")

        except (FileNotFoundError, OSError) as e:
            QMessageBox.critical(self, "Recorder Error", str(e))

    def launch_capture_wizard(self):
        errors = self.setup_vm.validate_paths(self.test_signal_path_var.text(), self.measurement_dir_var.text())
        if errors:
            QMessageBox.critical(
                self,
                "Error",
                "Please ensure the test signal and measurement directory are valid before recording.",
            )
            return

        try:
            name, groups = self.layout_vm.select_layout(self.layout_var.currentText())

            settings = RecorderSettings(
                measurement_dir=self.measurement_dir_var.text(),
                test_signal=self.test_signal_path_var.text(),
                playback_device=self.playback_device_var.currentText().split(":")[0],
                recording_device=self.recording_device_var.currentText().split(":")[0],
                output_channels=self.channel_mappings.get("output_channels", []),
                input_channels=self.channel_mappings.get("input_channels", []),
            )

            def prompt(msg: str) -> None:
                QMessageBox.information(self, "Capture Wizard", msg)

            def message(msg: str) -> None:
                self.append_output(msg)

            self.recorder_vm.run_capture_wizard(
                name,
                groups,
                settings,
                prompt_fn=prompt,
                message_fn=message,
                progress_callback=self.update_record_progress,
            )
        except (FileNotFoundError, OSError) as e:
            QMessageBox.critical(self, "Capture Wizard Error", str(e))

    def update_compensation_file_state(self):
        is_custom = self.compensation_type_var.currentText().lower() == "custom"
        self.compensation_custom_widget.setVisible(is_custom)
        self.compensation_file_path_var.setEnabled(is_custom)

    def browse_headphone_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select Headphone EQ File", "", "Wave Files (*.wav);;All Files (*)"
        )
        if file_path:
            self.headphone_file_path_var.setText(file_path)

    def browse_compensation_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select Compensation File", "", "CSV Files (*.csv);;All Files (*)"
        )
        if file_path:
            self.compensation_file_path_var.setText(file_path)

    def create_processing_options_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)
        summary = QLabel(
            """
        This tab lets you control how the impulse responses are interpreted and shaped,
        including decay filtering, loudness matching, balance, and room correction parameters.
        """
        )
        summary.setWordWrap(True)
        summary.setSizePolicy(summary.sizePolicy().horizontalPolicy(), QSizePolicy.Minimum)
        layout.addWidget(summary)
        # Processing Options Tab: Fine-tune BRIR processing parameters

        self.decay_time_var = QLineEdit()
        self.decay_time_var.setPlaceholderText("Recommended: 0.2")
        self.decay_time_toggle = QCheckBox("Enable")
        self.decay_time_toggle.setChecked(False)
        self.decay_time_var.setPlaceholderText("e.g., 0.2")
        self.decay_time_var.clear()
        layout.addLayout(self.labeled_row("Decay Time (seconds):", self.decay_time_var, self.decay_time_toggle))

        self.target_level_var = QLineEdit()
        self.target_level_var.setPlaceholderText("Recommended: -12.5")
        self.target_level_toggle = QCheckBox("Enable")
        self.target_level_toggle.setChecked(False)
        self.target_level_var.setPlaceholderText("e.g., -12.5")
        self.target_level_var.clear()
        layout.addLayout(self.labeled_row("Target Level (dB):", self.target_level_var, self.target_level_toggle))

        self.interactive_delays_var = QCheckBox("Interactive Delays")
        layout.addWidget(self.interactive_delays_var)

        self.channel_balance_var = QComboBox()
        self.channel_balance_var.addItem("Off", "off")
        self.channel_balance_var.addItem("Left", "left")
        self.channel_balance_var.addItem("Right", "right")
        self.channel_balance_var.addItem("Average", "avg")
        self.channel_balance_var.addItem("Minimum", "min")
        self.channel_balance_var.addItem("Mids", "mids")
        self.channel_balance_var.addItem("Trend", "trend")
        # Default strategy
        idx = self.channel_balance_var.findData("trend")
        if idx != -1:
            self.channel_balance_var.setCurrentIndex(idx)
        self.channel_balance_toggle = QCheckBox("Enable")
        self.channel_balance_toggle.setChecked(False)
        balance_row = QHBoxLayout()
        balance_row.addWidget(QLabel("Channel Balance:"))
        balance_row.addWidget(self.channel_balance_var)
        balance_row.addWidget(self.channel_balance_toggle)
        self.channel_balance_preview = QPushButton("Preview…")
        self.channel_balance_preview.clicked.connect(self.open_channel_balance_preview)
        balance_row.addWidget(self.channel_balance_preview)
        layout.addLayout(balance_row)

        self.room_correction_var = QCheckBox("Enable Room Correction")
        self.room_correction_var.stateChanged.connect(self.update_room_correction_fields)
        layout.addWidget(self.room_correction_var)

        self.room_target_path_var = QLineEdit()
        self.room_target_path_row = QWidget()
        row_layout = QHBoxLayout(self.room_target_path_row)
        row_layout.addWidget(QLabel("Room Target File (optional):"))
        row_layout.addWidget(self.room_target_path_var)
        row_layout.addWidget(QPushButton("Browse", clicked=self.browse_room_target))
        layout.addWidget(self.room_target_path_row)
        browse_room_target = QPushButton("Browse")
        browse_room_target.clicked.connect(self.browse_room_target)

        self.specific_limit_var = QLineEdit()
        self.specific_limit_var.setPlaceholderText("e.g., 700")
        self.specific_limit_toggle = QCheckBox("Enable")
        
        self.generic_limit_var = QLineEdit()
        self.generic_limit_var.setPlaceholderText("e.g., 500")
        self.generic_limit_toggle = QCheckBox("Enable")

        self.fr_combination_var = QComboBox()
        self.fr_combination_var.addItems(["average", "conservative"])
        self.fr_combination_toggle = QCheckBox("Enable")

        self.specific_limit_row_widget = QWidget()
        self.specific_limit_row = self.labeled_row(
            "Specific Limit (Hz):", self.specific_limit_var, self.specific_limit_toggle
        )
        self.specific_limit_row_widget.setLayout(self.specific_limit_row)
        self.generic_limit_row_widget = QWidget()
        self.generic_limit_row = self.labeled_row(
            "Generic Limit (Hz):", self.generic_limit_var, self.generic_limit_toggle
        )
        self.generic_limit_row_widget.setLayout(self.generic_limit_row)
        self.fr_combination_row_widget = QWidget()

        self.mic_calibration_path_var = QLineEdit()
        self.mic_calibration_path_var.setPlaceholderText("Optional microphone calibration file")
        mic_calib_browse = QPushButton("Browse")
        mic_calib_browse.clicked.connect(self.browse_mic_calibration_file)
        layout.addLayout(self.labeled_row("Mic Calibration File:", self.mic_calibration_path_var, mic_calib_browse))
        self.fr_combination_row = self.labeled_row(
            "FR Combination Method:", self.fr_combination_var, self.fr_combination_toggle
        )
        self.fr_combination_row_widget.setLayout(self.fr_combination_row)

        layout.addWidget(self.specific_limit_row_widget)
        layout.addWidget(self.generic_limit_row_widget)
        layout.addWidget(self.fr_combination_row_widget)

        self.add_processing_presets_section(layout)
        self.update_room_correction_fields()
        self.tabs.addTab(tab, "Processing Options")

    def update_room_correction_fields(self):
        is_enabled = self.room_correction_var.isChecked()
        self.room_target_path_row.setVisible(is_enabled)
        self.specific_limit_row_widget.setVisible(is_enabled)
        self.generic_limit_row_widget.setVisible(is_enabled)
        self.fr_combination_row_widget.setVisible(is_enabled)

    def browse_mic_calibration_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select Mic Calibration File", "", "Text Files (*.txt *.csv);;All Files (*)"
        )
        if file_path:
            self.mic_calibration_path_var.setText(file_path)

    def browse_room_target(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select Room Target File", "", "CSV Files (*.csv);;All Files (*)"
        )
        if file_path:
            self.room_target_path_var.setText(file_path)

    def add_processing_presets_section(self, layout: QVBoxLayout):
        group = QGroupBox("Processing Presets")
        box = QVBoxLayout(group)
        self.preset_list = QListWidget()
        box.addWidget(self.preset_list)
        btn_row = QHBoxLayout()
        load_btn = QPushButton("Load")
        save_btn = QPushButton("Save Current…")
        delete_btn = QPushButton("Delete")
        btn_row.addWidget(load_btn)
        btn_row.addWidget(save_btn)
        btn_row.addWidget(delete_btn)
        box.addLayout(btn_row)
        load_btn.clicked.connect(self.load_selected_preset)
        save_btn.clicked.connect(self.save_current_preset)
        delete_btn.clicked.connect(self.delete_selected_preset)
        layout.addWidget(group)
        self.refresh_presets()

    def add_room_presets_section(self, layout: QVBoxLayout):
        group = QGroupBox("Room Presets")
        box = QVBoxLayout(group)
        self.room_list = QListWidget()
        box.addWidget(self.room_list)
        self.room_notes_var = QTextEdit()
        self.room_notes_var.setFixedHeight(60)
        box.addLayout(self.labeled_row("Notes:", self.room_notes_var))
        btn_row = QHBoxLayout()
        load_btn = QPushButton("Load")
        save_btn = QPushButton("Save")
        delete_btn = QPushButton("Delete")
        import_btn = QPushButton("Import…")
        btn_row.addWidget(load_btn)
        btn_row.addWidget(save_btn)
        btn_row.addWidget(delete_btn)
        btn_row.addWidget(import_btn)
        box.addLayout(btn_row)
        load_btn.clicked.connect(self.load_selected_room_preset)
        save_btn.clicked.connect(self.save_current_room_preset)
        delete_btn.clicked.connect(self.delete_selected_room_preset)
        import_btn.clicked.connect(self.import_room_preset)
        layout.addWidget(group)
        self.refresh_room_presets()

    def labeled_row(self, label_text, widget, extra_widget=None):
        row = QHBoxLayout()
        row.addWidget(QLabel(label_text))
        row.addWidget(widget)
        if extra_widget:
            row.addWidget(extra_widget)
        return row

    def load_device_options(self):
        devices = sd.query_devices()
        self.playback_devices = [f"{i}: {d['name']}" for i, d in enumerate(devices) if d["max_output_channels"] > 0]
        self.recording_devices = [f"{i}: {d['name']}" for i, d in enumerate(devices) if d["max_input_channels"] > 0]

        self.playback_device_var.addItems(self.playback_devices)
        self.recording_device_var.addItems(self.recording_devices)

        if sd.default.device:
            if sd.default.device[1] < len(self.playback_devices):
                self.playback_device_var.setCurrentIndex(sd.default.device[1])
            if sd.default.device[0] < len(self.recording_devices):
                self.recording_device_var.setCurrentIndex(sd.default.device[0])

    def browse_test_signal(self):
        start_dir = os.path.dirname(self.test_signal_path_var.text() or "")
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "Select Test Signal File",
            start_dir,
            "Wave Files (*.wav);;Pickle Files (*.pkl);;All Files (*)",
        )
        if file_path:
            self.test_signal_path_var.setText(file_path)

    def browse_measurement_dir(self):
        start_dir = self.measurement_dir_var.text() or ""
        dir_path = QFileDialog.getExistingDirectory(self, "Select Measurement Directory", start_dir)
        if dir_path:
            self.measurement_dir_var.setText(dir_path)

    def toggle_advanced(self, checked):
        self.advanced_frame.setVisible(checked)
        self.advanced_toggle.setArrowType(Qt.DownArrow if checked else Qt.RightArrow)

    def handle_layout_change(self, text):
        if text == "Custom...":
            self.load_custom_layout()
            return
        self.selected_layout_name = text
        self.selected_layout = [SPEAKER_NAMES[i] for i in FORMAT_PRESETS[text]]
        self.auto_map_channels(silent=True)

    def load_custom_layout(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Select Layout File", "", "Text or JSON (*.txt *.json);;All Files (*)"
        )
        if not file_path:
            # Revert to previous selection
            self.layout_var.setCurrentText(self.selected_layout_name)
            return
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read().strip()
            try:

                names = json.loads(content)
                if isinstance(names, dict):
                    names = names.get("speakers", [])
            except json.JSONDecodeError:
                names = [n.strip() for n in content.split(",") if n.strip()]
            if not names:
                raise ValueError("No speakers defined in layout file")
            self.selected_layout_name = os.path.basename(file_path)
            self.selected_layout = names
            if self.layout_var.findText(self.selected_layout_name) == -1:
                self.layout_var.addItem(self.selected_layout_name)
            self.layout_var.setCurrentText(self.selected_layout_name)
        except (OSError, ValueError, json.JSONDecodeError) as e:
            QMessageBox.critical(self, "Layout Load Error", str(e))
            self.layout_var.setCurrentText(self.selected_layout_name)

    def save_layout_preset(self):
        try:
            from constants import save_user_layout_preset

            name, groups = self.selected_layout_name, [[sp] for sp in self.selected_layout]
            file_path, _ = QFileDialog.getSaveFileName(
                self, "Save Layout", f"{name}.json", "JSON Files (*.json);;All Files (*)"
            )
            if not file_path:
                return
            save_user_layout_preset(name, groups, file_path)
            QMessageBox.information(self, "Layout Saved", f"Layout saved to {file_path}")
            if self.layout_var.findText(name) == -1:
                self.layout_var.insertItem(self.layout_var.count() - 1, name)
        except (OSError, IOError) as e:
            QMessageBox.critical(self, "Save Layout Error", str(e))

    def import_layout_preset(self):
        try:
            from constants import load_and_register_user_layouts, save_user_layout_preset

            file_path, _ = QFileDialog.getOpenFileName(
                self,
                "Import Layout Preset",
                "",
                "JSON Files (*.json);;All Files (*)",
            )
            if not file_path:
                return
            layouts = load_and_register_user_layouts(file_path)
            for name, groups in layouts.items():
                save_user_layout_preset(name, groups)
                if self.layout_var.findText(name) == -1:
                    self.layout_var.insertItem(self.layout_var.count() - 1, name)
            QMessageBox.information(self, "Layouts Imported", f"Imported {len(layouts)} layout(s)")
        except (OSError, IOError, json.JSONDecodeError) as e:
            QMessageBox.critical(self, "Import Layout Error", str(e))

    def map_channels(self):
        from PySide6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QFormLayout

        dialog = QDialog(self)
        dialog.setWindowTitle("Channel Mapping")

        main_layout = QHBoxLayout()

        playback_idx = int(self.playback_device_var.currentText().split(":")[0])
        record_idx = int(self.recording_device_var.currentText().split(":")[0])

        playback_channels = sd.query_devices(playback_idx)["max_output_channels"]
        record_channels = sd.query_devices(record_idx)["max_input_channels"]

        speaker_labels = self.selected_layout
        mic_labels = ["Mic Left", "Mic Right"]

        self.speaker_channel_vars = []
        self.mic_channel_vars = []

        # Speaker layout
        speaker_layout = QFormLayout()
        speaker_layout.addRow(QLabel(f"Speaker Channels ({self.selected_layout_name})"))
        for i, label in enumerate(speaker_labels):
            box = QComboBox()
            box.addItems([str(x + 1) for x in range(playback_channels)])
            box.setCurrentIndex(i if i < playback_channels else 0)
            self.speaker_channel_vars.append(box)
            speaker_layout.addRow(label, box)

        # Mic layout
        mic_layout = QFormLayout()
        mic_layout.addRow(QLabel("Microphone Channels (Recording)"))
        for j, label in enumerate(mic_labels):
            box = QComboBox()
            box.addItems([str(x + 1) for x in range(record_channels)])
            box.setCurrentIndex(j if j < record_channels else 0)
            self.mic_channel_vars.append(box)
            mic_layout.addRow(label, box)

        main_layout.addLayout(speaker_layout)
        main_layout.addLayout(mic_layout)

        bottom_layout = QVBoxLayout()
        save_btn = QPushButton("Save Mappings")
        save_btn.clicked.connect(lambda: self.save_channel_mappings(dialog))
        bottom_layout.addLayout(main_layout)
        bottom_layout.addWidget(save_btn)

        dialog.setLayout(bottom_layout)
        dialog.exec()

    def open_layout_viewer(self):
        """Interactive viewer for arranging speaker icons."""
        dialog = QDialog(self)
        dialog.setWindowTitle("Layout Viewer")

        main_layout = QVBoxLayout(dialog)

        view_selector = QComboBox()
        view_selector.addItems(["Top", "Side", "Isometric"])
        main_layout.addWidget(view_selector)

        scene = QGraphicsScene()
        view = QGraphicsView(scene)
        view.setRenderHint(QPainter.Antialiasing)
        view.setBackgroundBrush(QColor("#121212"))
        main_layout.addWidget(view)

        # Reference grid
        for r in range(50, 201, 50):
            circle = QGraphicsEllipseItem(-r, -r, r * 2, r * 2)
            circle.setPen(QPen(QColor("#444"), 1, Qt.DashLine))
            circle.setBrush(Qt.NoBrush)
            circle.setZValue(-1)
            scene.addItem(circle)

        center_item = QGraphicsEllipseItem(-5, -5, 10, 10)
        center_item.setBrush(QBrush(QColor("#888")))
        center_item.setPen(QPen(Qt.NoPen))
        center_item.setZValue(-1)
        scene.addItem(center_item)

        class SpeakerItem(QGraphicsEllipseItem):
            def __init__(self, name):
                super().__init__(-15, -15, 30, 30)
                grad = QRadialGradient(0, 0, 15, 0, 0)
                grad.setColorAt(0.0, QColor("#00d0ff"))
                grad.setColorAt(1.0, QColor("#003872"))
                self.setBrush(QBrush(grad))
                self.setPen(QPen(QColor("#09f"), 1.5))
                self.setFlag(QGraphicsEllipseItem.ItemIsMovable, True)
                self.setAcceptHoverEvents(True)
                self.name = name
                text = QGraphicsTextItem(name, self)
                text.setPos(-text.boundingRect().width() / 2, -30)
                self.setData(0, name)
                self.setToolTip(name)

            def hoverEnterEvent(self, event):
                self.setPen(QPen(QColor("#fff"), 2))
                super().hoverEnterEvent(event)

            def hoverLeaveEvent(self, event):
                self.setPen(QPen(QColor("#09f"), 1.5))
                super().hoverLeaveEvent(event)

        items = []
        radius = 150

        def default_pos(index, name, view_type):
            if view_type == "Side":
                x = -radius + (2 * radius) * index / max(1, len(self.selected_layout) - 1)
                y = -60 if name.startswith("T") else 60
                return QPointF(x, y)
            elif view_type == "Isometric":
                angle = (360 / len(self.selected_layout)) * index
                rad = math.radians(angle)
                x = radius * math.cos(rad)
                y = radius * math.sin(rad) * 0.5
                if name.startswith("T"):
                    y -= 40
                return QPointF(x, y)
            # Top view
            angle = (360 / len(self.selected_layout)) * index
            rad = math.radians(angle)
            return QPointF(radius * math.cos(rad), radius * math.sin(rad))

        for i, name in enumerate(self.selected_layout):
            item = SpeakerItem(name)
            scene.addItem(item)
            items.append(item)

        def update_positions():
            view_type = view_selector.currentText()
            for idx, item in enumerate(items):
                pos = getattr(self, "layout_positions", {}).get(item.name)
                if pos is None:
                    pos = default_pos(idx, item.name, view_type)
                item.setPos(pos)

        update_positions()

        btn_row = QHBoxLayout()
        save_btn = QPushButton("Save")
        reset_btn = QPushButton("Reset")
        close_btn = QPushButton("Close")
        btn_row.addWidget(save_btn)
        btn_row.addWidget(reset_btn)
        btn_row.addWidget(close_btn)
        main_layout.addLayout(btn_row)

        def save_positions():
            self.layout_positions = {item.data(0): item.pos() for item in items}
            measurement_dir = self.measurement_dir_var.text().strip()
            if measurement_dir:
                pos_file = os.path.join(measurement_dir, "speaker_positions.json")
                delay_file = os.path.join(measurement_dir, "speaker_delays.json")
                positions = {k: (p.x(), p.y()) for k, p in self.layout_positions.items()}
                try:
                    self.layout_vm.save_positions(positions, pos_file)
                    self.layout_vm.delays_from_positions(pos_file, delay_file)
                except OSError as e:
                    QMessageBox.warning(dialog, "Save Error", str(e))
            dialog.accept()

        def reset_positions():
            view_type = view_selector.currentText()
            for idx, item in enumerate(items):
                target = default_pos(idx, item.name, view_type)
                item.setPos(target)

        save_btn.clicked.connect(save_positions)
        reset_btn.clicked.connect(reset_positions)
        close_btn.clicked.connect(dialog.reject)
        view_selector.currentTextChanged.connect(update_positions)

        dialog.exec()

    def open_layout_wizard(self):
        dialog = QDialog(self)
        dialog.setWindowTitle("Layout Wizard")

        main_layout = QVBoxLayout()
        main_layout.addWidget(QLabel("Prepare or verify a capture folder for the selected layout."))

        layout_combo = QComboBox()
        layout_combo.addItems(SPEAKER_LAYOUTS.keys())
        current = self.layout_var.currentText()
        if current in SPEAKER_LAYOUTS:
            layout_combo.setCurrentText(current)
        main_layout.addLayout(self.labeled_row("Layout:", layout_combo))

        dir_edit = QLineEdit(self.measurement_dir_var.text())
        browse_btn = QPushButton("Browse")

        def browse_dir():
            d = QFileDialog.getExistingDirectory(dialog, "Select Directory", dir_edit.text())
            if d:
                dir_edit.setText(d)

        browse_btn.clicked.connect(browse_dir)
        main_layout.addLayout(self.labeled_row("Directory:", dir_edit, browse_btn))

        output_box = QTextEdit()
        output_box.setReadOnly(True)
        main_layout.addWidget(output_box)

        btn_row = QHBoxLayout()
        init_btn = QPushButton("Initialize")
        verify_btn = QPushButton("Verify")
        close_btn = QPushButton("Close")
        btn_row.addWidget(init_btn)
        btn_row.addWidget(verify_btn)
        btn_row.addWidget(close_btn)
        main_layout.addLayout(btn_row)

        def run_action(func):
            name, groups = self.layout_vm.select_layout(layout_combo.currentText())
            buffer = io.StringIO()
            try:
                with redirect_stdout(buffer):
                    func(name, groups, dir_edit.text())
            except (OSError, ValueError) as e:
                QMessageBox.critical(dialog, "Error", str(e))
            output_box.setPlainText(buffer.getvalue())

        init_btn.clicked.connect(lambda: run_action(self.layout_vm.init_layout))
        verify_btn.clicked.connect(lambda: run_action(self.layout_vm.verify_layout))
        close_btn.clicked.connect(dialog.accept)

        dialog.setLayout(main_layout)
        dialog.exec()

    def gather_processing_settings(self) -> ProcessingSettings:
        return ProcessingSettings(
            measurement_dir=self.measurement_dir_var.text(),
            test_signal=self.test_signal_path_var.text(),
            decay_time=self.decay_time_var.text() if self.decay_time_toggle.isChecked() else "",
            target_level=self.target_level_var.text() if self.target_level_toggle.isChecked() else "",
            channel_balance_enabled=self.channel_balance_toggle.isChecked(),
            channel_balance=self.channel_balance_var.currentData(),
            specific_limit_enabled=self.specific_limit_toggle.isChecked(),
            specific_limit=self.specific_limit_var.text(),
            generic_limit_enabled=self.generic_limit_toggle.isChecked(),
            generic_limit=self.generic_limit_var.text(),
            fr_combination_enabled=self.fr_combination_toggle.isChecked(),
            fr_combination_method=self.fr_combination_var.currentText(),
            room_correction=self.room_correction_var.isChecked(),
            room_target=self.room_target_path_var.text(),
            mic_calibration=self.mic_calibration_path_var.text(),
            enable_compensation=self.enable_compensation_var.isChecked(),
            headphone_eq_enabled=self.headphone_eq_toggle.isChecked(),
            headphone_file=self.headphone_file_path_var.text(),
            compensation_type=(
                self.compensation_file_path_var.text()
                if self.compensation_type_var.currentText().lower() == "custom"
                else self.compensation_type_var.currentText().lower().replace("-field", "")
            ),
            diffuse_field=self.diffuse_field_toggle.isChecked(),
            x_curve_action=self.x_curve_action_var.currentText(),
            x_curve_type=self.x_curve_type_var.currentText(),
            x_curve_in_capture=self.x_curve_in_capture_var.isChecked(),
            interactive_delays=self.interactive_delays_var.isChecked(),
        )

    def gather_preset_data(self) -> dict:
        data = asdict(self.gather_processing_settings())
        data["layout"] = self.selected_layout_name
        return data

    def refresh_presets(self):
        self.preset_list.clear()
        for name in preset_manager.load_presets().keys():
            self.preset_list.addItem(name)

    def save_current_preset(self):
        name, ok = QInputDialog.getText(self, "Save Preset", "Preset name:")
        if not ok or not name:
            return
        preset_manager.save_preset(name, self.gather_preset_data())
        self.refresh_presets()

    def load_selected_preset(self):
        item = self.preset_list.currentItem()
        if not item:
            return
        name = item.text()
        data = preset_manager.load_presets().get(name)
        if data is None:
            return
        if name == "None":
            QMessageBox.information(self, "Preset Loaded", "Reverting to default processing settings")
            self.apply_preset({})
            return
        reply = QMessageBox.question(
            self,
            "Load Preset",
            f"Apply preset '{name}' with these settings?\n{json.dumps(data, indent=2)}",
            QMessageBox.Ok | QMessageBox.Cancel,
        )
        if reply == QMessageBox.Ok:
            self.apply_preset(data)

    def delete_selected_preset(self):
        item = self.preset_list.currentItem()
        if not item:
            return
        preset_manager.delete_preset(item.text())
        self.refresh_presets()

    def refresh_profiles(self):
        self.profile_list.clear()
        for name in user_profiles.load_profiles().keys():
            self.profile_list.addItem(name)

    def save_current_profile(self):
        name, ok = QInputDialog.getText(self, "Save Profile", "Profile name:")
        if not ok or not name:
            return
        routing = [int(x) for x in self.profile_routing_var.text().split(",") if x.strip().isdigit()]
        from models import UserProfile

        profile = UserProfile(
            brir_dir=self.profile_brir_var.text(),
            tracking_calibration=self.profile_cal_var.text(),
            output_routing=routing,
            latency=int(self.profile_latency_var.text() or 0),
            headphone_file=self.profile_headphone_var.text(),
            playback_device=self.profile_playback_device_var.text(),
        )
        user_profiles.save_profile(name, profile)
        self.refresh_profiles()

    def load_selected_profile(self):
        item = self.profile_list.currentItem()
        if not item:
            return
        name = item.text()
        data = user_profiles.load_profiles().get(name)
        if data is None:
            return
        if name == "None":
            QMessageBox.information(self, "Profile Loaded", "Reverting to default profile")
            data = {}
        else:
            reply = QMessageBox.question(
                self,
                "Load Profile",
                f"Apply profile '{name}' with these settings?\n{json.dumps(data, indent=2)}",
                QMessageBox.Ok | QMessageBox.Cancel,
            )
            if reply != QMessageBox.Ok:
                return
        self.profile_brir_var.setText(data.get("brir_dir", ""))
        self.profile_cal_var.setText(data.get("tracking_calibration", ""))
        self.profile_routing_var.setText(",".join(str(x) for x in data.get("output_routing", [])))
        self.profile_latency_var.setText(str(data.get("latency", 0)))
        self.profile_headphone_var.setText(data.get("headphone_file", ""))
        self.profile_playback_device_var.setText(data.get("playback_device", ""))

    def delete_selected_profile(self):
        item = self.profile_list.currentItem()
        if not item:
            return
        user_profiles.delete_profile(item.text())
        self.refresh_profiles()

    def gather_room_preset_data(self):
        from models import RoomPreset

        return RoomPreset(
            brir_dir=self.profile_brir_var.text(),
            measurement_dir=self.measurement_dir_var.text(),
            notes=self.room_notes_var.toPlainText(),
            measurement_date=datetime.date.today().isoformat(),
        )

    def refresh_room_presets(self):
        self.room_list.clear()
        for name in room_presets.load_room_presets().keys():
            self.room_list.addItem(name)

    def save_current_room_preset(self):
        name, ok = QInputDialog.getText(self, "Save Room", "Room name:")
        if not ok or not name:
            return
        room_presets.save_room_preset(name, self.gather_room_preset_data())
        self.refresh_room_presets()

    def load_selected_room_preset(self):
        item = self.room_list.currentItem()
        if not item:
            return
        name = item.text()
        data = room_presets.load_room_presets().get(name)
        if data is None:
            return
        if name == "None":
            QMessageBox.information(self, "Room Loaded", "Reverting to default room")
            data = {}
        else:
            reply = QMessageBox.question(
                self,
                "Load Room",
                f"Apply room '{name}' with these settings?\n{json.dumps(data, indent=2)}",
                QMessageBox.Ok | QMessageBox.Cancel,
            )
            if reply != QMessageBox.Ok:
                return
        self.profile_brir_var.setText(data.get("brir_dir", ""))
        self.measurement_dir_var.setText(data.get("measurement_dir", ""))
        self.room_notes_var.setPlainText(data.get("notes", ""))

    def delete_selected_room_preset(self):
        item = self.room_list.currentItem()
        if not item:
            return
        room_presets.delete_room_preset(item.text())
        self.refresh_room_presets()

    def import_room_preset(self):
        file_path, _ = QFileDialog.getOpenFileName(self, "Import Room Preset", "", "JSON Files (*.json);;All Files (*)")
        if file_path:
            try:
                room_presets.import_room_preset(file_path)
                self.refresh_room_presets()
            except (OSError, ValueError) as e:
                QMessageBox.critical(self, "Import Error", str(e))

    def apply_preset(self, data: dict):
        self.measurement_dir_var.setText(data.get("measurement_dir", ""))
        self.test_signal_path_var.setText(data.get("test_signal", ""))
        decay = data.get("decay_time", "")
        self.decay_time_var.setText(decay)
        self.decay_time_toggle.setChecked(bool(decay))
        target = data.get("target_level", "")
        self.target_level_var.setText(target)
        self.target_level_toggle.setChecked(bool(target))
        self.channel_balance_toggle.setChecked(data.get("channel_balance_enabled", False))
        idx = self.channel_balance_var.findData(data.get("channel_balance"))
        if idx >= 0:
            self.channel_balance_var.setCurrentIndex(idx)
        self.specific_limit_toggle.setChecked(data.get("specific_limit_enabled", False))
        self.specific_limit_var.setText(data.get("specific_limit", ""))
        self.generic_limit_toggle.setChecked(data.get("generic_limit_enabled", False))
        self.generic_limit_var.setText(data.get("generic_limit", ""))
        self.fr_combination_toggle.setChecked(data.get("fr_combination_enabled", False))
        idx = self.fr_combination_var.findText(data.get("fr_combination_method", ""))
        if idx >= 0:
            self.fr_combination_var.setCurrentIndex(idx)
        self.room_correction_var.setChecked(data.get("room_correction", False))
        self.update_room_correction_fields()
        self.room_target_path_var.setText(data.get("room_target", ""))
        self.mic_calibration_path_var.setText(data.get("mic_calibration", ""))
        self.enable_compensation_var.setChecked(data.get("enable_compensation", False))
        self.headphone_eq_toggle.setChecked(data.get("headphone_eq_enabled", False))
        self.headphone_file_path_var.setText(data.get("headphone_file", ""))
        comp = data.get("compensation_type", "")
        idx = self.compensation_type_var.findText(comp.capitalize() if comp else "Diffuse-field")
        if idx >= 0:
            self.compensation_type_var.setCurrentIndex(idx)
        if self.compensation_type_var.currentText().lower() == "custom":
            self.compensation_file_path_var.setText(comp)
        self.diffuse_field_toggle.setChecked(data.get("diffuse_field", False))
        idx = self.x_curve_action_var.findText(data.get("x_curve_action", "None"))
        if idx >= 0:
            self.x_curve_action_var.setCurrentIndex(idx)
        idx = self.x_curve_type_var.findText(data.get("x_curve_type", X_CURVE_DEFAULT_TYPE))
        if idx >= 0:
            self.x_curve_type_var.setCurrentIndex(idx)
        self.x_curve_in_capture_var.setChecked(data.get("x_curve_in_capture", False))
        self.interactive_delays_var.setChecked(data.get("interactive_delays", False))
        layout_name = data.get("layout", self.selected_layout_name)
        if self.layout_var.findText(layout_name) == -1:
            self.layout_var.insertItem(self.layout_var.count() - 1, layout_name)
        self.layout_var.setCurrentText(layout_name)
        self.selected_layout_name = layout_name

    def create_profile_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)

        self.profile_list = QListWidget()
        layout.addWidget(self.profile_list)

        self.profile_brir_var = QLineEdit()
        self.profile_cal_var = QLineEdit()
        self.profile_routing_var = QLineEdit()
        self.profile_latency_var = QLineEdit()
        self.profile_headphone_var = QLineEdit()
        self.profile_playback_device_var = QLineEdit()

        layout.addLayout(self.labeled_row("BRIR Dir:", self.profile_brir_var))
        layout.addLayout(self.labeled_row("Tracking Cal:", self.profile_cal_var))
        layout.addLayout(self.labeled_row("Output Routing:", self.profile_routing_var))
        layout.addLayout(self.labeled_row("Latency:", self.profile_latency_var))
        layout.addLayout(self.labeled_row("Headphone EQ:", self.profile_headphone_var))
        layout.addLayout(self.labeled_row("Playback Device:", self.profile_playback_device_var))

        btn_row = QHBoxLayout()
        load_btn = QPushButton("Load")
        save_btn = QPushButton("Save")
        delete_btn = QPushButton("Delete")
        btn_row.addWidget(load_btn)
        btn_row.addWidget(save_btn)
        btn_row.addWidget(delete_btn)
        layout.addLayout(btn_row)

        load_btn.clicked.connect(self.load_selected_profile)
        save_btn.clicked.connect(self.save_current_profile)
        delete_btn.clicked.connect(self.delete_selected_profile)

        self.tabs.addTab(tab, "Profiles")
        self.refresh_profiles()

    def create_visualization_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(8)
        layout.addWidget(
            QLabel(
                """
        View example plots or visualizations of processed frequency responses to
        help verify measurement accuracy and processing behavior.
        """
            )
        )
        # Visualization Tab: View frequency response plots
        from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
        from matplotlib.figure import Figure

        self.figure = Figure()
        self.canvas = FigureCanvas(self.figure)
        layout.addWidget(self.canvas)

        control_row = QHBoxLayout()
        self.plot_selector = QComboBox()
        self.plot_selector.currentTextChanged.connect(self.display_selected_plot)
        refresh_btn = QPushButton("Refresh")
        refresh_btn.clicked.connect(self.load_plot_files)
        control_row.addWidget(self.plot_selector)
        control_row.addWidget(refresh_btn)
        layout.addLayout(control_row)

        self.image_label = QLabel()
        self.image_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(self.image_label)

        self.plot_button = QPushButton("Plot Example")
        self.plot_button.clicked.connect(self.plot_example)
        layout.addWidget(self.plot_button)

        self.measurement_dir_var.textChanged.connect(self.load_plot_files)
        self.load_plot_files()

        self.tabs.addTab(tab, "Visualization")
  
    def save_log(self):
        try:
            content = self.output_text.toPlainText()
            default_name = f"earprint_log_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
            file_path, _ = QFileDialog.getSaveFileName(
                self, "Save Log", default_name, "Text Files (*.txt);;All Files (*)"
            )
            if file_path:
                with open(file_path, "w") as f:
                    f.write(content)
                QMessageBox.information(self, "Log Saved", f"Log saved to {file_path}")
        except OSError as e:
            QMessageBox.critical(self, "Save Log Error", str(e))

    def browse_log_file(self):
        file_path, _ = QFileDialog.getSaveFileName(
            self, "Select Log File", "earprint.log", "Text Files (*.txt);;All Files (*)"
        )
        if file_path:
            self.log_file_path.setText(file_path)

    def append_output(self, text: str, color: Optional[str] = None) -> None:
        if color:
            self.output_text.append(f"<span style='color: {color};'>" + text + "</span>")
        else:
            self.output_text.append(text)
        if self.log_file_check.isChecked() and self.log_file_path.text():
            try:
                with open(self.log_file_path.text(), "a") as f:
                    f.write(text + "\n")
            except OSError:
                pass

    def update_record_progress(self, progress: float, remaining: float) -> None:
        self.record_progress.show()
        self.record_progress.setValue(int(progress * 100))
        if progress >= 1.0:
            self.remaining_label.setText("")
            self.record_progress.hide()
        else:
            self.remaining_label.setText(f"{remaining:.1f}s remaining")
        QApplication.processEvents()

    def export_hesuvi_preset(self):
        try:
            errors = self.setup_vm.validate_paths(measurement_dir=self.measurement_dir_var.text())
            if "measurement_dir" in errors:
                QMessageBox.warning(self, "Export Error", "Invalid measurement directory")
                return
            src = os.path.join(self.measurement_dir_var.text(), "hesuvi.wav")
            if not self.setup_vm.file_exists(src):
                QMessageBox.warning(self, "Export Error", "hesuvi.wav not found. Run processing first.")
                return
            dest, _ = QFileDialog.getSaveFileName(
                self, "Export Hesuvi Preset", "hesuvi.wav", "WAV Files (*.wav);;All Files (*)"
            )
            if dest:
                with open(src, "rb") as fsrc, open(dest, "wb") as fdst:
                    fdst.write(fsrc.read())
                QMessageBox.information(self, "Export Complete", f"Preset exported to {dest}")
        except OSError as e:
            QMessageBox.critical(self, "Export Error", str(e))

    def plot_example(self):
        ax = self.figure.add_subplot(111)
        ax.clear()
        ax.plot([0, 1, 2, 3], [10, 1, 20, 3])
        ax.set_title("Example Plot")
        self.canvas.draw()

    def load_plot_files(self):
        self.plot_selector.clear()
        errors = self.setup_vm.validate_paths(measurement_dir=self.measurement_dir_var.text())
        if "measurement_dir" in errors:
            self.image_label.setText("No plots found")
            return

        plots_dir = os.path.join(self.measurement_dir_var.text(), "plots")
        if not self.setup_vm.directory_exists(plots_dir):
            self.image_label.setText("No plots found")
            return
        files = []
        for root, _, names in os.walk(plots_dir):
            for n in names:
                if n.lower().endswith(".png"):
                    rel = os.path.relpath(os.path.join(root, n), plots_dir)
                    files.append(rel)
        files.sort()
        self.plot_selector.addItems(files)
        if files:
            self.plot_selector.setCurrentIndex(0)
            self.display_selected_plot()
        else:
            self.image_label.setText("No plots found")

    def display_selected_plot(self):
        rel_path = self.plot_selector.currentText()
        if not rel_path:
            return
        errors = self.setup_vm.validate_paths(measurement_dir=self.measurement_dir_var.text())
        if "measurement_dir" in errors:
            self.image_label.setText("Plot not found")
            return

        plot_path = os.path.join(self.measurement_dir_var.text(), "plots", rel_path)
        if self.setup_vm.file_exists(plot_path):
            pix = QPixmap(plot_path)
            self.image_label.setPixmap(pix)
            self.image_label.setScaledContents(True)
        else:
            self.image_label.setText("Plot not found")

    def toggle_monitor(self, checked):
        if checked:
            try:
                dev_idx = int(self.recording_device_var.currentText().split(":")[0])
            except (ValueError, IndexError):
                dev_idx = None
            try:
                out_idx = int(self.playback_device_var.currentText().split(":")[0])
            except (ValueError, IndexError):
                out_idx = None
            samplerate = None
            if dev_idx is not None:
                try:
                    samplerate = int(sd.query_devices(dev_idx)["default_samplerate"])
                except (KeyError, ValueError, sd.PortAudioError):
                    samplerate = None
            self.level_monitor = LevelMonitor(device=dev_idx, samplerate=samplerate or 48000)
            self.monitor_thread = threading.Thread(target=self.level_monitor.start, daemon=True)
            self.monitor_thread.start()
            self.output_monitor = LevelMonitor(device=out_idx, samplerate=samplerate or 48000, loopback=True)
            self.output_thread = threading.Thread(target=self.output_monitor.start, daemon=True)
            self.output_thread.start()
            self.monitor_timer.start(100)
            self.monitor_btn.setText("Stop Monitor")
        else:
            self.monitor_timer.stop()
            if self.level_monitor:
                self.level_monitor.stop()
            if self.output_monitor:
                self.output_monitor.stop()
            if self.monitor_thread and self.monitor_thread.is_alive():
                self.monitor_thread.join(timeout=1.0)
            if self.output_thread and self.output_thread.is_alive():
                self.output_thread.join(timeout=1.0)
            self.level_monitor = None
            self.monitor_thread = None
            self.output_monitor = None
            self.output_thread = None
            self.level_bar.setValue(0)
            self.output_level_bar.setValue(0)
            self.monitor_btn.setText("Start Monitor")

    def read_monitor_level(self):
        if self.level_monitor:
            try:
                db = self.level_monitor.queue.get_nowait()
                value = int(np.clip((db + 60) / 60 * 100, 0, 100)) if db != -np.inf else 0
                self.level_bar.setValue(value)
            except queue.Empty:
                pass
        if self.output_monitor:
            try:
                db = self.output_monitor.queue.get_nowait()
                value = int(np.clip((db + 60) / 60 * 100, 0, 100)) if db != -np.inf else 0
                self.output_level_bar.setValue(value)
            except queue.Empty:
                pass

    def save_channel_mappings(self, dialog):
        speakers = [int(box.currentText()) - 1 for box in self.speaker_channel_vars]
        mics = [int(box.currentText()) - 1 for box in self.mic_channel_vars]
        self.channel_mappings = {"output_channels": speakers, "input_channels": mics}
        QMessageBox.information(self, "Channel Mappings", "Channel mappings saved successfully.")
        dialog.accept()

    def auto_map_channels(self, silent: bool = False):
        """Automatically assign sequential channels based on device capabilities."""
        try:
            playback_idx = int(self.playback_device_var.currentText().split(":")[0])
            record_idx = int(self.recording_device_var.currentText().split(":")[0])
            playback_channels = sd.query_devices(playback_idx)["max_output_channels"]
            record_channels = sd.query_devices(record_idx)["max_input_channels"]
            spk_count = len(self.selected_layout)
            self.channel_mappings = {
                "output_channels": list(range(min(playback_channels, spk_count))),
                "input_channels": list(range(min(record_channels, 2))),
            }
            if not silent:
                QMessageBox.information(self, "Auto Map", "Channel mappings assigned automatically.")
        except (ValueError, IndexError, KeyError, sd.PortAudioError) as e:
            if not silent:
                QMessageBox.critical(self, "Auto Map Error", str(e))

    def open_channel_balance_preview(self):
        from PySide6.QtCore import Qt

        dialog = QDialog(self)
        dialog.setWindowTitle("Channel Balance Preview")

        main_layout = QVBoxLayout()

        file_layout = QHBoxLayout()
        file_layout.addWidget(QLabel("Audio File:"))
        file_var = QLineEdit()
        file_layout.addWidget(file_var)
        browse_btn = QPushButton("Browse")
        file_layout.addWidget(browse_btn)
        main_layout.addLayout(file_layout)

        slider_layout = QHBoxLayout()
        slider_layout.addWidget(QLabel("Right Gain:"))
        slider = QSlider(Qt.Horizontal)
        slider.setRange(-100, 100)
        slider.setValue(0)
        slider_layout.addWidget(slider)
        gain_label = QLabel("0.0 dB")
        slider_layout.addWidget(gain_label)
        main_layout.addLayout(slider_layout)

        button_layout = QHBoxLayout()
        play_btn = QPushButton("Play")
        stop_btn = QPushButton("Stop")
        apply_btn = QPushButton("Apply")
        close_btn = QPushButton("Close")
        button_layout.addWidget(play_btn)
        button_layout.addWidget(stop_btn)
        button_layout.addWidget(apply_btn)
        button_layout.addWidget(close_btn)
        main_layout.addLayout(button_layout)

        def update_label(value):
            gain_label.setText(f"{value/10:.1f} dB")

        slider.valueChanged.connect(update_label)

        def browse_file():
            file_path, _ = QFileDialog.getOpenFileName(
                dialog, "Select Audio File", "", "Wave Files (*.wav);;All Files (*)"
            )
            if file_path:
                file_var.setText(file_path)

        browse_btn.clicked.connect(browse_file)

        def play():
            if not self.setup_vm.file_exists(file_var.text()):
                QMessageBox.critical(dialog, "Error", "Please select a valid audio file.")
                return
            data, fs = sf.read(file_var.text(), always_2d=True)
            if data.shape[1] < 2:
                QMessageBox.critical(dialog, "Error", "Audio file must be stereo.")
                return
            gain = 10 ** ((slider.value() / 10) / 20)
            data[:, 1] *= gain
            sd.stop()
            sd.play(data, fs)

        play_btn.clicked.connect(play)
        stop_btn.clicked.connect(sd.stop)

        def apply():
            gain_db = slider.value() / 10
            cli_val = f"{gain_db:.1f}"
            label = f"{cli_val} dB"
            # Find existing entry with same data
            index = self.channel_balance_var.findData(cli_val)
            if index == -1:
                self.channel_balance_var.addItem(label, cli_val)
                index = self.channel_balance_var.count() - 1
            self.channel_balance_var.setCurrentIndex(index)
            self.channel_balance_toggle.setChecked(True)
            sd.stop()
            dialog.accept()

        apply_btn.clicked.connect(apply)

        def close_dialog():
            sd.stop()
            dialog.close()

        close_btn.clicked.connect(close_dialog)

        dialog.setLayout(main_layout)
        dialog.exec()

    def setup_shortcuts(self):
        QShortcut(
            QKeySequence("Meta+1"),
            self,
            activated=lambda: self.tabs.setCurrentIndex(
                self.tabs.indexOf(self.tabs.widget(0))  # Assumes Execution tab is at index 0
            ),
        )

    def run_startup_checks(self):
        """Validate core paths and audio device access on launch."""
        if not hasattr(self, "startup_status_label"):
            return

        issues = []
        # Validate default test signal and measurement directory paths
        errors = self.setup_vm.validate_paths()
        for item in errors:
            if item == "test_signal":
                issues.append("test signal")
            elif item == "measurement_dir":
                issues.append("measurement dir")

        # Check that at least one audio device is available
        try:
            sd.query_devices()
        except Exception:
            issues.append("audio device access")

        if issues:
            self.startup_status_label.setText("Startup Check: problem with " + ", ".join(issues))
            self.startup_status_label.setStyleSheet("color: red;")
        else:
            self.startup_status_label.setText("Startup Check: OK")
            self.startup_status_label.setStyleSheet("color: green;")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = EarprintGUI()
    window.show()
    sys.exit(app.exec())
