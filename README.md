# Earprint

Earprint is a professional macOS application for capturing and processing binaural impulse responses (HRIR/BRIR). It combines a modern SwiftUI interface with powerful Python-based signal processing to create personalized spatial audio profiles for headphones and room acoustics.

## What is Earprint?

Earprint transforms your headphones into an accurate speaker virtualization system by capturing how sound travels from speakers to your ears in your specific listening environment. Using binaural microphones and exponential sine sweep measurements, Earprint creates personalized Head-Related Impulse Responses (HRIRs) and Binaural Room Impulse Responses (BRIRs) that make headphones sound like speakers in a real room.

## Key Features

### **Measurement & Capture**
- Interactive capture wizard with step-by-step guidance
- Support for multiple speaker layouts (stereo, 5.1, 7.1, Atmos)
- Binaural microphone recording with real-time monitoring
- Automated sweep signal generation and playback
- Head tracking integration for dynamic measurements

### **Advanced Processing**
- Sophisticated impulse response processing pipeline
- Room correction and acoustic compensation
- Headphone equalization and frequency response matching
- Multiple output formats (WAV, HeSuVi, Pro Tools AAX)
- Customizable processing presets and user profiles

### **Professional Interface**
- Native macOS SwiftUI application
- Real-time visualization of frequency responses
- Interactive charts and measurement analysis
- Preset management for different rooms and setups
- Comprehensive logging and debugging tools

### **Cross-Platform Tools**
- Command-line utilities for batch processing
- Python API for custom workflows
- Real-time convolution engine for testing
- Comprehensive test suite and development tools

## System Requirements

- **macOS**: 13.5 or later
- **Xcode**: 16.4 or later (for building from source)
- **Python**: 3.9 or later
- **Hardware**: Binaural microphones, audio interface, speakers

## Installation

### Option 1: Building from Source (Recommended for Development)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/n1299cb/Earprint.git
   cd Earprint
   ```

2. **Open in Xcode:**
   ```bash
   open Earprint.xcodeproj
   ```

3. **Build and run:**
   - Select the `Earprint` scheme in Xcode
   - Choose **Product > Run** or press `⌘R`
   - The app will build and launch automatically

### Option 2: Command Line Build

1. **Build with Xcode command line tools:**
   ```bash
   cd Earprint
   xcodebuild -project Earprint.xcodeproj -scheme Earprint -configuration Release build
   ```

2. **Run the built application:**
   ```bash
   open build/Release/Earprint.app
   ```

## Python Environment Setup

Earprint requires Python dependencies for its signal processing backend:

### **Automatic Setup (Recommended)**
The macOS app includes an embedded Python runtime. Dependencies are automatically managed when you first run the application.

### **Manual Setup for Development**

1. **Create a virtual environment:**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Install additional macOS dependencies:**
   ```bash
   # Install PortAudio for audio device access
   brew install portaudio
   
   # Reinstall Python audio dependencies
   pip install -U -r requirements.txt
   ```

4. **Verify installation:**
   ```bash
   python3 -c "import sounddevice, json; print(json.dumps(sounddevice.query_devices()))"
   ```

## Repository Structure

```
Earprint/
├── Earprint.xcodeproj/          # Xcode project file
├── Earprint/                    # Main application source
│   ├── Sources/                 # SwiftUI views and models
│   ├── Resources/               # App resources and assets
│   └── Info.plist              # App configuration
├── Scripts/                     # Python processing tools
│   ├── earprint.py             # Main processing pipeline
│   ├── capture_wizard.py       # Interactive recording workflow
│   ├── realtime_convolution.py # Real-time audio processing
│   └── tests/                  # Python test suite
├── Resources/
│   └── EmbeddedPython/         # Bundled Python runtime
├── data/                       # Sample measurements and demos
└── docs/                       # Documentation
```

## Quick Start

### **Try the Demo**
Test Earprint without measurement hardware:

```bash
cd Scripts
python earprint.py --test_signal=../data/sweep-6.15s-48000Hz-32bit-2.93Hz-24000Hz.pkl --dir_path=../data/demo
```

This processes sample measurements and creates `hrir.wav` and `hesuvi.wav` files for testing with spatial audio software.

### **Create Your First Measurement**

1. **Launch Earprint** and connect your binaural microphones
2. **Go to Setup tab** and configure your speaker layout
3. **Use Capture Wizard** to record measurements for each speaker
4. **Process measurements** in the Post-Processing tab
5. **Export results** for use with your preferred spatial audio software

## Command Line Tools

Earprint includes several standalone utilities:

- **`earprint.py`** - Complete processing pipeline
- **`capture_wizard.py`** - Interactive recording workflow  
- **`realtime_convolution.py`** - Audio convolution engine
- **`generate_layout.py`** - Speaker layout generator

Example usage:
```bash
python earprint.py --dir_path /path/to/measurements --output_format hesuvi
python capture_wizard.py --layout stereo --dir /path/to/output
```

## Testing

Run the comprehensive test suite:

```bash
cd Scripts
python -m pytest tests/
```

## Troubleshooting

### **Empty Device Lists**
If audio devices don't appear:
```bash
brew install portaudio
pip install -U -r requirements.txt
```

### **Python Module Errors**
Ensure all dependencies are installed:
```bash
pip install -r requirements.txt
```

### **Build Issues**
- Verify Xcode 16.4+ is installed
- Clean build folder: **Product > Clean Build Folder**
- Reset package dependencies if needed

## Development

For contributor setup and advanced development instructions, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

To build Pro Tools AAX plugins, see [docs/AAX_PLUGIN.md](docs/AAX_PLUGIN.md).

## License

Earprint is released under the MIT License. See [LICENSE](LICENSE) for details.

Modifications and additions © 2025 Blaring Sound LLC are also licensed under the MIT License.
