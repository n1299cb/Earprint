import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var configurationVM: ConfigurationViewModel
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    @State private var selectedTab: SettingsTab = .general
    @State private var showingResetAlert = false
    
    // MARK: - Audio Device State (matching SetupView structure)
    @State private var playbackDevices: [AudioDevice] = []
    @State private var recordingDevices: [AudioDevice] = []
    @State private var selectedPlaybackDevice = ""
    @State private var selectedRecordingDevice = ""
    @State private var availableLayouts: [String] = []
    @State private var selectedLayout = "7.1"
    @State private var channelMapping: [String: [Int]] = [:]
    @State private var showingChannelMapping = false
    
    // MARK: - Basic Settings
    @State private var defaultMeasurementDir = ""
    @State private var defaultTestSignal = ""
    @State private var autoSaveConfiguration = true
    @State private var enableDetailedLogging = false
    @State private var rememberWindowPosition = true
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case audio = "Audio Devices"
        case advanced = "Advanced"
        
        var id: String { rawValue }

// MARK: - Simple Channel Mapping View
struct SimpleChannelMappingView: View {
    let playbackChannels: Int
    let recordingChannels: Int
    let speakerLabels: [String]
    @Binding var channelMapping: [String: [Int]]
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    
    @State private var speakerSelections: [Int] = []
    @State private var micSelections: [Int] = []
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Channel Mapping")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    saveMapping()
                    isPresented = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            HStack(alignment: .top, spacing: 40) {
                // Speaker Channels
                VStack(alignment: .leading, spacing: 16) {
                    Text("Speaker Channels (\(playbackChannels) available)")
                        .font(.headline)
                    
                    if speakerLabels.isEmpty {
                        Text("No speakers for this layout")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(speakerLabels.enumerated()), id: \.offset) { index, label in
                            HStack {
                                Text(label)
                                    .frame(width: 60, alignment: .leading)
                                
                                Picker("Channel", selection: Binding(
                                    get: {
                                        index < speakerSelections.count ? speakerSelections[index] : 0
                                    },
                                    set: { newValue in
                                        while speakerSelections.count <= index {
                                            speakerSelections.append(0)
                                        }
                                        speakerSelections[index] = newValue
                                    }
                                )) {
                                    ForEach(0..<playbackChannels, id: \.self) { channel in
                                        Text("Channel \(channel + 1)").tag(channel)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                        }
                    }
                }
                
                // Microphone Channels
                VStack(alignment: .leading, spacing: 16) {
                    Text("Microphone Channels (\(recordingChannels) available)")
                        .font(.headline)
                    
                    let micLabels = ["Left Mic", "Right Mic"]
                    ForEach(Array(micLabels.enumerated()), id: \.offset) { index, label in
                        HStack {
                            Text(label)
                                .frame(width: 80, alignment: .leading)
                            
                            Picker("Channel", selection: Binding(
                                get: {
                                    index < micSelections.count ? micSelections[index] : index
                                },
                                set: { newValue in
                                    while micSelections.count <= index {
                                        micSelections.append(index)
                                    }
                                    micSelections[index] = newValue
                                }
                            )) {
                                ForEach(0..<max(recordingChannels, 1), id: \.self) { channel in
                                    Text("Channel \(channel + 1)").tag(channel)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                    }
                }
            }
            
            // Warnings
            if playbackChannels < speakerLabels.count {
                Text("⚠️ Playback device has fewer channels (\(playbackChannels)) than required speakers (\(speakerLabels.count))")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            
            if recordingChannels < 2 {
                Text("⚠️ Recording device should have at least 2 channels for binaural recording")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            
            Spacer()
        }
        .padding(24)
        .onAppear {
            initializeSelections()
        }
    }
    
    private func initializeSelections() {
        speakerSelections = channelMapping["output_channels"] ?? Array(0..<speakerLabels.count)
        micSelections = channelMapping["input_channels"] ?? [0, 1]
        
        // Ensure we have the right number of selections
        while speakerSelections.count < speakerLabels.count {
            speakerSelections.append(speakerSelections.count)
        }
        while micSelections.count < 2 {
            micSelections.append(micSelections.count)
        }
    }
    
    private func saveMapping() {
        channelMapping["output_channels"] = Array(speakerSelections.prefix(speakerLabels.count))
        channelMapping["input_channels"] = Array(micSelections.prefix(2))
    }
}
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .audio: return "speaker.wave.3"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }
    
    // AudioDevice struct matching SetupView
    struct AudioDevice: Identifiable {
        let id: Int
        let name: String
        let maxOutput: Int
        let maxInput: Int
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            
        } detail: {
            // Detail View
            Group {
                switch selectedTab {
                case .general:
                    generalSettingsView
                case .audio:
                    audioSettingsView
                case .advanced:
                    advancedSettingsView
                }
            }
            .navigationTitle(selectedTab.rawValue)
            .navigationSplitViewColumnWidth(min: 500, ideal: 700)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Reset to Defaults") {
                    showingResetAlert = true
                }
                .buttonStyle(.bordered)
            }
        }
        .alert("Reset Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
        .sheet(isPresented: $showingChannelMapping) {
            // Use the existing ChannelMappingView from your project
            if let speakerLabels = fetchSpeakerLabelsArray(layout: selectedLayout) {
                ChannelMappingView(
                    playbackChannels: selectedPlaybackChannels,
                    recordingChannels: selectedRecordingChannels,
                    speakerLabels: speakerLabels,
                    playbackDevice: selectedPlaybackDevice,
                    channelMapping: $channelMapping,
                    isPresented: $showingChannelMapping,
                    onSave: {
                        // Channel mapping saved
                    }
                )
                .frame(minWidth: 600, minHeight: 400)
            } else {
                VStack {
                    Text("Unable to load speaker layout")
                    Button("Close") {
                        showingChannelMapping = false
                    }
                }
                .padding()
            }
        }
        .onAppear {
            loadCurrentSettings()
            loadAudioDevices()
            loadLayouts()
        }
    }
    
    // MARK: - General Settings
    private var generalSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Default Paths", icon: "folder") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Default Measurement Directory",
                            description: "The default location for saving measurements and recordings"
                        ) {
                            HStack {
                                Text(defaultMeasurementDir.isEmpty ?
                                     "No directory selected" :
                                     URL(fileURLWithPath: defaultMeasurementDir).lastPathComponent)
                                    .foregroundColor(defaultMeasurementDir.isEmpty ? .secondary : .primary)
                                
                                Spacer()
                                
                                Button("Browse") {
                                    selectMeasurementDirectory()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        SettingsRow(
                            title: "Default Test Signal",
                            description: "The default audio file used for measurements"
                        ) {
                            HStack {
                                Text(defaultTestSignal.isEmpty ?
                                     "No test signal selected" :
                                     URL(fileURLWithPath: defaultTestSignal).lastPathComponent)
                                    .foregroundColor(defaultTestSignal.isEmpty ? .secondary : .primary)
                                
                                Spacer()
                                
                                Button("Browse") {
                                    selectTestSignal()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                SettingsSection(title: "Application Behavior", icon: "app") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Auto-save Configuration",
                            description: "Automatically save configuration changes"
                        ) {
                            Toggle("", isOn: $autoSaveConfiguration)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Show Detailed Logs",
                            description: "Display verbose logging information during processing"
                        ) {
                            Toggle("", isOn: $enableDetailedLogging)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Remember Window Position",
                            description: "Restore window size and position on app launch"
                        ) {
                            Toggle("", isOn: $rememberWindowPosition)
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Audio Settings
    private var audioSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Audio Devices", icon: "speaker.wave.3") {
                    VStack(spacing: 16) {
                        HStack {
                            Button("Refresh Devices") {
                                loadAudioDevices()
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Text("\(playbackDevices.count) playback, \(recordingDevices.count) recording devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        SettingsRow(
                            title: "Default Playback Device",
                            description: "The audio output device used for test signal playback"
                        ) {
                            Picker("Playback Device", selection: $selectedPlaybackDevice) {
                                Text("System Default").tag("")
                                ForEach(playbackDevices) { device in
                                    Text("\(device.name) (\(device.maxOutput) out)")
                                        .tag(String(device.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 300)
                        }
                        
                        SettingsRow(
                            title: "Default Recording Device",
                            description: "The audio input device used for capturing measurements"
                        ) {
                            Picker("Recording Device", selection: $selectedRecordingDevice) {
                                Text("System Default").tag("")
                                ForEach(recordingDevices) { device in
                                    Text("\(device.name) (\(device.maxInput) in)")
                                        .tag(String(device.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 300)
                        }
                    }
                }
                
                SettingsSection(title: "Speaker Layout", icon: "speakers") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Default Speaker Layout",
                            description: "The default speaker configuration for measurements"
                        ) {
                            Picker("Layout", selection: $selectedLayout) {
                                ForEach(availableLayouts, id: \.self) { layout in
                                    Text(layout).tag(layout)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                        
                        HStack {
                            Button("Channel Mapping") {
                                showingChannelMapping = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedPlaybackDevice.isEmpty || selectedRecordingDevice.isEmpty)
                            
                            Button("Auto Map Channels") {
                                autoMapChannels()
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedPlaybackDevice.isEmpty || selectedRecordingDevice.isEmpty)
                            
                            Spacer()
                            
                            if !channelMappingStatus.isEmpty {
                                Text(channelMappingStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !channelWarning.isEmpty {
                            Text(channelWarning)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Advanced Settings
    private var advancedSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Performance", icon: "speedometer") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Processing Threads",
                            description: "Number of threads to use for parallel processing"
                        ) {
                            Picker("Threads", selection: .constant(0)) {
                                Text("Auto").tag(0)
                                ForEach(1...ProcessInfo.processInfo.processorCount, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                
                SettingsSection(title: "Python Environment", icon: "terminal") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Python Executable",
                            description: "Path to the Python interpreter used for processing"
                        ) {
                            HStack {
                                Text("Using embedded Python")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Browse") {
                                    // Future: Allow custom Python selection
                                }
                                .buttonStyle(.bordered)
                                .disabled(true)
                            }
                        }
                        
                        SettingsRow(
                            title: "Scripts Directory",
                            description: "Location of the Python processing scripts"
                        ) {
                            HStack {
                                Text("Using bundled scripts")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                        }
                    }
                }
                
                SettingsSection(title: "Debugging", icon: "ladybug") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Enable Debug Mode",
                            description: "Enable verbose logging and debug output"
                        ) {
                            Toggle("", isOn: .constant(false))
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Save Intermediate Files",
                            description: "Keep intermediate processing files for debugging"
                        ) {
                            Toggle("", isOn: .constant(false))
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Computed Properties
    private var selectedPlaybackChannels: Int {
        playbackDevices.first(where: { String($0.id) == selectedPlaybackDevice })?.maxOutput ?? 0
    }
    
    private var selectedRecordingChannels: Int {
        recordingDevices.first(where: { String($0.id) == selectedRecordingDevice })?.maxInput ?? 0
    }
    
    private var channelMappingStatus: String {
        let outputChannels = channelMapping["output_channels"]?.count ?? 0
        let inputChannels = channelMapping["input_channels"]?.count ?? 0
        if outputChannels > 0 || inputChannels > 0 {
            return "Mapped: \(outputChannels) out, \(inputChannels) in"
        }
        return ""
    }
    
    private var channelWarning: String {
        guard !selectedPlaybackDevice.isEmpty && !selectedRecordingDevice.isEmpty else { return "" }
        
        var warnings: [String] = []
        let speakerCount = fetchSpeakerLabels(layout: selectedLayout).count
        
        if selectedPlaybackChannels < speakerCount && speakerCount > 0 {
            warnings.append("Playback device only has \(selectedPlaybackChannels) channels while layout requires \(speakerCount)")
        }
        if selectedRecordingChannels < 2 {
            let suffix = selectedRecordingChannels == 1 ? "" : "s"
            warnings.append("Recording device only has \(selectedRecordingChannels) channel\(suffix); two are required")
        }
        
        return warnings.joined(separator: ". ")
    }
    
    // MARK: - Helper Methods
    private func selectMeasurementDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            defaultMeasurementDir = url.path
        }
    }
    
    private func selectTestSignal() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        
        if panel.runModal() == .OK, let url = panel.url {
            defaultTestSignal = url.path
        }
    }
    
    private func loadAudioDevices() {
        print("🔍 Starting audio device enumeration...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            #if os(macOS)
            // Try CoreAudio first, but keep Python fallback
            let (caDevices, defaultInput, defaultOutput) = CoreAudioUtils.queryDevices()
            if !caDevices.isEmpty {
                let all = caDevices.map { d in
                    AudioDevice(id: Int(d.deviceID), name: d.name, maxOutput: d.maxOutput, maxInput: d.maxInput)
                }
                DispatchQueue.main.async {
                    self.playbackDevices = all.filter { $0.maxOutput > 0 }
                    self.recordingDevices = all.filter { $0.maxInput > 0 }
                    
                    // Set defaults if not already set
                    if self.selectedPlaybackDevice.isEmpty, let def = defaultOutput,
                       let dev = self.playbackDevices.first(where: { $0.id == Int(def) }) {
                        self.selectedPlaybackDevice = String(dev.id)
                    }
                    if self.selectedRecordingDevice.isEmpty, let def = defaultInput,
                       let dev = self.recordingDevices.first(where: { $0.id == Int(def) }) {
                        self.selectedRecordingDevice = String(dev.id)
                    }
                    print("✅ Audio devices loaded via CoreAudio: \(self.playbackDevices.count) output, \(self.recordingDevices.count) input")
                }
                return
            }
            #endif
            
            // Python fallback - essential for full functionality
            self.loadAudioDevicesViaPython()
        }
    }
    
    private func loadAudioDevicesViaPython() {
        guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
            print("❌ Scripts directory not found in bundle")
            return
        }
        
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        
        if let embeddedPythonURL = Bundle.main.resourceURL?.appendingPathComponent("EmbeddedPython/Python.framework/Versions/3.9/bin/python3"),
           FileManager.default.fileExists(atPath: embeddedPythonURL.path) {
            // Use embedded Python
            process.executableURL = embeddedPythonURL
            process.arguments = [
                "-c",
                "import json, sounddevice as sd, sys; json.dump({'devices': sd.query_devices(), 'default': list(sd.default.device)}, sys.stdout)"
            ]
            process.environment = [
                "PYTHONHOME": embeddedPythonURL.deletingLastPathComponent().deletingLastPathComponent().path,
                "PYTHONPATH": scriptsRoot.path
            ]
            print("🔍 Using embedded Python for audio devices")
        } else {
            // Fallback to system Python
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                "-c",
                "import json, sounddevice as sd, sys; json.dump({'devices': sd.query_devices(), 'default': list(sd.default.device)}, sys.stdout)"
            ]
            print("🔍 Using system Python for audio devices")
        }
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            
            // Add a reasonable timeout but don't kill it immediately
            DispatchQueue.global().asyncAfter(deadline: .now() + 15.0) {
                if process.isRunning {
                    print("⚠️ Python process taking longer than expected, but keeping it running...")
                }
            }
            
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if !errorData.isEmpty, let errorString = String(data: errorData, encoding: .utf8) {
                print("⚠️ Python stderr: \(errorString)")
            }
            
            guard
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let devs = obj["devices"] as? [[String: Any]]
            else {
                print("❌ Failed to parse audio device JSON from Python")
                if let dataString = String(data: data, encoding: .utf8) {
                    print("Python output: \(dataString)")
                }
                return
            }
            
            let defaults = (obj["default"] as? [Int]) ?? [-1, -1]
            let all = devs.enumerated().map { idx, d in
                AudioDevice(
                    id: idx,
                    name: (d["name"] as? String) ?? "Unknown Device",
                    maxOutput: d["max_output_channels"] as? Int ?? 0,
                    maxInput: d["max_input_channels"] as? Int ?? 0
                )
            }
            
            DispatchQueue.main.async {
                self.playbackDevices = all.filter { $0.maxOutput > 0 }
                self.recordingDevices = all.filter { $0.maxInput > 0 }
                
                if self.selectedPlaybackDevice.isEmpty, defaults[1] >= 0,
                   let dev = self.playbackDevices.first(where: { $0.id == defaults[1] }) {
                    self.selectedPlaybackDevice = String(dev.id)
                }
                if self.selectedRecordingDevice.isEmpty, defaults[0] >= 0,
                   let dev = self.recordingDevices.first(where: { $0.id == defaults[0] }) {
                    self.selectedRecordingDevice = String(dev.id)
                }
                
                print("✅ Audio devices loaded via Python: \(self.playbackDevices.count) output, \(self.recordingDevices.count) input")
            }
            
        } catch {
            print("❌ Failed to execute Python process for audio devices: \(error)")
        }
    }
    
    private func loadLayouts() {
        print("🔍 Starting layout loading...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
                print("❌ Scripts directory not found for layouts")
                // Fallback to basic layouts
                DispatchQueue.main.async {
                    self.availableLayouts = ["5.1", "7.1", "9.1.6", "Stereo", "Mono"]
                    if self.selectedLayout.isEmpty {
                        self.selectedLayout = "7.1"
                    }
                }
                return
            }
            
            let process = Process()
            process.currentDirectoryURL = scriptsRoot
            
            if let embeddedPythonURL = Bundle.main.resourceURL?.appendingPathComponent("EmbeddedPython/Python.framework/Versions/3.9/bin/python3"),
               FileManager.default.fileExists(atPath: embeddedPythonURL.path) {
                // Use embedded Python
                process.executableURL = embeddedPythonURL
                process.arguments = [
                    "-c",
                    "import json,constants,sys; json.dump(sorted(constants.SPEAKER_LAYOUTS.keys()), sys.stdout)"
                ]
                process.environment = [
                    "PYTHONHOME": embeddedPythonURL.deletingLastPathComponent().deletingLastPathComponent().path,
                    "PYTHONPATH": scriptsRoot.path
                ]
                print("🔍 Using embedded Python for speaker layouts")
            } else {
                // Fallback to system Python
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "python3",
                    "-c",
                    "import json,constants,sys; json.dump(sorted(constants.SPEAKER_LAYOUTS.keys()), sys.stdout)"
                ]
                print("🔍 Using system Python for speaker layouts")
            }
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                if !errorData.isEmpty, let errorString = String(data: errorData, encoding: .utf8) {
                    print("⚠️ Python stderr for layouts: \(errorString)")
                }
                
                if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    DispatchQueue.main.async {
                        self.availableLayouts = arr
                        if self.selectedLayout.isEmpty, let first = arr.first {
                            self.selectedLayout = first
                        }
                        print("✅ Loaded \(arr.count) speaker layouts from Python")
                    }
                } else {
                    print("❌ Failed to parse speaker layouts from Python")
                    if let dataString = String(data: data, encoding: .utf8) {
                        print("Python output: \(dataString)")
                    }
                    // Fallback to basic layouts
                    DispatchQueue.main.async {
                        self.availableLayouts = ["5.1", "7.1", "9.1.6", "Stereo", "Mono"]
                        if self.selectedLayout.isEmpty {
                            self.selectedLayout = "7.1"
                        }
                        print("✅ Using fallback speaker layouts")
                    }
                }
                
            } catch {
                print("❌ Failed to execute Python process for layouts: \(error)")
                // Fallback to basic layouts
                DispatchQueue.main.async {
                    self.availableLayouts = ["5.1", "7.1", "9.1.6", "Stereo", "Mono"]
                    if self.selectedLayout.isEmpty {
                        self.selectedLayout = "7.1"
                    }
                    print("✅ Using fallback speaker layouts due to error")
                }
            }
        }
    }
    
    private func autoMapChannels() {
        guard
            let pDev = playbackDevices.first(where: { String($0.id) == selectedPlaybackDevice }),
            let rDev = recordingDevices.first(where: { String($0.id) == selectedRecordingDevice })
        else { return }
        
        let speakerCount = fetchSpeakerLabels(layout: selectedLayout).count
        if speakerCount == 0 { return }
        
        channelMapping["output_channels"] = Array(0..<min(pDev.maxOutput, speakerCount))
        channelMapping["input_channels"] = Array(0..<min(rDev.maxInput, 2))
    }
    
    private func fetchSpeakerLabels(layout: String) -> [String] {
        // This mirrors the fetchSpeakerLabels() function from SetupView
        guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
            print("❌ Scripts directory not found for speaker labels")
            // Return basic fallback labels
            switch layout {
            case "5.1":
                return ["FL", "FR", "C", "LFE", "SL", "SR"]
            case "7.1":
                return ["FL", "FR", "C", "LFE", "SL", "SR", "BL", "BR"]
            case "9.1.6":
                return ["FL", "FR", "C", "LFE", "SL", "SR", "BL", "BR", "TFL", "TFR", "TML", "TMR", "TBL", "TBR", "TC", "BC"]
            case "Stereo":
                return ["FL", "FR"]
            case "Mono":
                return ["C"]
            default:
                return []
            }
        }
        
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        
        if let embeddedPythonURL = Bundle.main.resourceURL?.appendingPathComponent("EmbeddedPython/Python.framework/Versions/3.9/bin/python3"),
           FileManager.default.fileExists(atPath: embeddedPythonURL.path) {
            // Use embedded Python
            process.executableURL = embeddedPythonURL
            process.arguments = [
                "-c",
                "import json,constants,sys; print(json.dumps([c for g in constants.SPEAKER_LAYOUTS.get('" + layout + "', []) for c in g]))"
            ]
            process.environment = [
                "PYTHONHOME": embeddedPythonURL.deletingLastPathComponent().deletingLastPathComponent().path,
                "PYTHONPATH": scriptsRoot.path
            ]
        } else {
            // Fallback to system Python
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                "-c",
                "import json,constants,sys; print(json.dumps([c for g in constants.SPEAKER_LAYOUTS.get('" + layout + "', []) for c in g]))"
            ]
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                print("✅ Loaded \(arr.count) speaker labels for layout '\(layout)' from Python")
                return arr
            } else {
                print("⚠️ Failed to parse speaker labels from Python, using fallback")
                if let dataString = String(data: data, encoding: .utf8) {
                    print("Python output: \(dataString)")
                }
            }
        } catch {
            print("⚠️ Failed to execute Python for speaker labels: \(error)")
        }
        
        // Fallback to basic labels if Python fails
        switch layout {
        case "5.1":
            return ["FL", "FR", "C", "LFE", "SL", "SR"]
        case "7.1":
            return ["FL", "FR", "C", "LFE", "SL", "SR", "BL", "BR"]
        case "9.1.6":
            return ["FL", "FR", "C", "LFE", "SL", "SR", "BL", "BR", "TFL", "TFR", "TML", "TMR", "TBL", "TBR", "TC", "BC"]
        case "Stereo":
            return ["FL", "FR"]
        case "Mono":
            return ["C"]
        default:
            return []
        }
    }
    
    private func fetchSpeakerLabelsArray(layout: String) -> [String]? {
        let labels = fetchSpeakerLabels(layout: layout)
        return labels.isEmpty ? nil : labels
    }
    
    private func resetToDefaults() {
        defaultMeasurementDir = ""
        defaultTestSignal = ""
        autoSaveConfiguration = true
        enableDetailedLogging = false
        rememberWindowPosition = true
        selectedPlaybackDevice = ""
        selectedRecordingDevice = ""
        selectedLayout = "7.1"
        channelMapping = [:]
    }
    
    private func loadCurrentSettings() {
        // Load current settings from configurationVM if available
    }
    
    private func saveSettings() {
        // Save settings to configurationVM
    }
}

// MARK: - Supporting Views
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content
    
    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.headline)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            content()
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let description: String
    let content: () -> Content
    
    init(title: String, description: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            content()
        }
        .padding(.vertical, 4)
    }
}
