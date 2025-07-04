# Earprint

Earprint is a macOS application for capturing and processing binaural impulse responses.
It is distributed as a Swift package with bundled Python scripts.

## Repository layout

- `EarprintGUI/` – Swift package containing the macOS application
- `EarprintGUI/Scripts/` – Python tools used by the GUI and available as CLI utilities
- `EarprintGUI/Resources/EmbeddedPython/` – location for the embedded Python interpreter

## Building the app

The application is built with the Swift Package Manager. From the project root:

```bash
cd EarprintGUI
swift build -c release
```

`swift run EarprintGUI` launches the GUI while developing. When distributing the app you must embed a Python runtime. Copy the official macOS distribution so that the directory tree matches the following structure:

```text
EmbeddedPython
└── Python.framework
    └── Versions
        └── 3.9 -> 3.9.6
```

As noted in `Resources/EmbeddedPython/README.md`, `bin/python3` should end up at
`EarprintGUI.app/Contents/Resources/EmbeddedPython/Python.framework/Versions/3.9/bin/python3`.

## Python environment

The Python scripts require Python 3.9 or later with several third‑party packages.
Typical dependencies include `numpy`, `scipy`, `matplotlib`, `tabulate`,
`sounddevice` and `pyfftw`. Install them with `pip` before running the tools or
executing the test suite.

## Installing Python Dependencies

1. **Create a virtual environment (recommended):**

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```

2. **Install the packages:**

   ```bash
   pip install -r requirements.txt
   ```

Alternatively, you can install the packages directly into the bundled Python framework used by the application:

```bash
EarprintGUI/Resources/EmbeddedPython/Python.framework/Versions/3.9/bin/python3 -m pip install -r requirements.txt
```

Once the dependencies are installed you can run the test suite with `pytest`.

## Command line tools

The `Scripts` directory exposes a few utilities that can also be used outside the GUI:

- `earprint.py` – full processing pipeline for turning recorded sweeps into HRIRs.
  Invoke with `--dir_path <capture_dir>` and various options controlling equalisation and output.
- `capture_wizard.py` – interactive console workflow for making new recordings.
  Provide `--layout` and `--dir` to define the speaker layout and target folder.
- `realtime_convolution.py` – offline convolver for testing BRIR files:
  `python realtime_convolution.py input.wav output.wav hrir.wav --block_size 1024`.
- `generate_layout.py` – helper that creates a capture folder and README listing
  the expected sweep files.

Each processing run also writes CSV data to the measurement's `plots`
directory. These files contain frequency responses for visualization in the
SwiftUI Charts view.

## Running the tests

The Python tests live under `EarprintGUI/Scripts/tests`. After installing the
required dependencies run:

```bash
pytest
```

The tests assume the same directory layout as the repository and rely on the
packages mentioned above.

## Preferences

The Setup view lets you choose where measurements are stored. If you
often work in the same folder, open **Settings** in the menu bar and set a
default measurement directory. New sessions will start there, but you can
override the location from Setup.