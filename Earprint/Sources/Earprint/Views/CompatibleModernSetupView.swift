#if canImport(SwiftUI)
import SwiftUI
#if canImport(CoreAudio)
import CoreAudio
#endif
import AppKit

struct CompatibleModernSetupView: View {
    @ObservedObject var viewModel: ModernProcessingViewModel
    @Binding var measurementDir: String
    @Binding var testSignal: String
    @Binding var channelBalance: String
    @Binding var targetLevel: String
    @Binding var selectedLayout: String
    @Binding var playbackDevice: String
    @Binding var recordingDevice: String
    @Binding var channelMapping: [String: [Int]]

    struct AudioDevice: Identifiable {
        let id: Int
        let name: String
        let maxOutput: Int
        let maxInput: Int
    }

    @State private var playbackDevices: [AudioDevice] = []
    @State private var recordingDevices: [AudioDevice] = []
    @State private var showMapping = false
    @State private var testSignalValid: Bool = true
    @StateObject private var recordingVM = RecordingViewModel()
    @State private var inputLevel: Double = 0
    @State private var outputLevel: Double = 0
    @State private var isMonitoring: Bool = false
    @State private var inputProcess: Process? = nil
    @State private var outputProcess: Process? = nil
    @State private var inputPipe: Pipe? = nil
    @State private var outputPipe: Pipe? = nil
    @State private var layouts: [String] = []
    @State private var channelWarning: String = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Header Section
                headerSection
                
                // Quick Actions
                quickActionsSection
                
                // Audio Configuration
                audioConfigurationSection
                
                // Layout Configuration
                layoutConfigurationSection
                
                // Audio Monitoring
                audioMonitoringSection
                
                // Processing Log
                if !viewModel.log.isEmpty {
                    processingLogSection
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .navigationTitle("Audio Setup")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh Devices") {
                    loadDevices()
                }
            }
        }
        .onAppear {
            print("DEBUG: App onAppear - selectedLayout: '\(selectedLayout)'")
            print("DEBUG: App onAppear - layouts array: \(layouts)")
            
            // Force refresh if layouts are empty
            if layouts.isEmpty {
                print("DEBUG: Layouts empty, forcing load...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loadLayoutsSync()
                }
            }
            
            initializeView()
        }
        .onChange(of: measurementDir) { _ in
            Task { validatePaths() }
        }
        .onChange(of: selectedLayout) { _ in
            Task { validateChannelCount() }
        }
        .onChange(of: playbackDevice) { _ in
            Task { validateChannelCount() }
        }
        .onChange(of: recordingDevice) { _ in
            Task { validateChannelCount() }
        }
        .sheet(isPresented: $showMapping) {
            channelMappingSheet
        }
        .alert("Error", isPresented: $recordingVM.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recordingVM.errorMessage)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Recording")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if recordingVM.latestRecording.isEmpty {
                        Text("No recordings yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    } else {
                        TextField("Recording name", text: $recordingVM.recordingName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.title3)
                    }
                }
                
                Spacer()
                
                if recordingVM.measurementHasFiles {
                    Button(action: saveRecording) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save Recording")
                        }
                    }
                    .controlSize(.large)
                }
            }
            
            if !recordingVM.latestRecording.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Latest: \(recordingVM.latestRecording)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Setup")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack(spacing: 12) {
                SimpleActionCard(
                    title: "Layout Wizard",
                    icon: "speaker.wave.3",
                    action: { viewModel.layoutWizard(layout: selectedLayout, dir: measurementDir) }
                )
                .disabled(selectedLayout.isEmpty)
                
                SimpleActionCard(
                    title: "Map Channels",
                    icon: "point.3.connected.trianglepath.dotted",
                    action: { showMapping = true }
                )
                .disabled(fetchSpeakerLabels(layout: selectedLayout).isEmpty)
                
                SimpleActionCard(
                    title: "Auto Map",
                    icon: "wand.and.stars",
                    action: autoMapChannels
                )
            }
        }
    }
    
    // MARK: - Audio Configuration
    
    private var audioConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Configuration")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Test Signal
                SimpleConfigRow(title: "Test Signal") {
                    HStack {
                        TextField("Select test signal file", text: $testSignal)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(testSignalValid ? Color.green : Color.red, lineWidth: 1)
                            )
                        
                        Button("Browse") {
                            if let path = openPanel(directory: false, startPath: testSignal) {
                                testSignal = path
                            }
                        }
                    }
                }
                
                Divider()
                
                // Playback Device
                SimpleConfigRow(title: "Playback Device") {
                    Picker("Playback Device", selection: $playbackDevice) {
                        if playbackDevices.isEmpty {
                            Text("No devices available").tag("")
                        } else {
                            ForEach(playbackDevices) { device in
                                Text("\(device.name) (\(device.maxInput) in / \(device.maxOutput) out)")
                                    .tag(String(device.id))
                            }
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(playbackDevices.isEmpty)
                }
                
                // Recording Device
                SimpleConfigRow(title: "Recording Device") {
                    Picker("Recording Device", selection: $recordingDevice) {
                        if recordingDevices.isEmpty {
                            Text("No devices available").tag("")
                        } else {
                            ForEach(recordingDevices) { device in
                                Text("\(device.name) (\(device.maxInput) in / \(device.maxOutput) out)")
                                    .tag(String(device.id))
                            }
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(recordingDevices.isEmpty)
                }
                
                if !channelWarning.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(channelWarning)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
    
    // MARK: - Layout Configuration
    
    private var layoutConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speaker Layout")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                SimpleConfigRow(title: "Layout Type") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Selected: \(selectedLayout.isEmpty ? "None" : selectedLayout)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Force refresh button for debugging
                            Button("Refresh") {
                                loadLayoutsSync()
                            }
                            .font(.caption)
                        }
                        
                        // Use a different approach with explicit state key
                        Picker("Layout", selection: $selectedLayout) {
                            ForEach(layouts, id: \.self) { layout in
                                Text(layout).tag(layout)
                            }
                            
                            // Add empty option if no layouts loaded
                            if layouts.isEmpty {
                                Text("Loading...").tag("")
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .id("layout-picker-\(layouts.count)") // Force recreation when layouts change
                        .disabled(layouts.isEmpty)
                        
                        Text("\(layouts.count) layouts available")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                SimpleConfigRow(title: "Channel Balance") {
                    Picker("Channel Balance", selection: $channelBalance) {
                        Text("Off").tag("off")
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                        Text("Average").tag("avg")
                        Text("Minimum").tag("min")
                        Text("Mids").tag("mids")
                        Text("Trend").tag("trend")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                SimpleConfigRow(title: "Target Level") {
                    TextField("Target Level (dB)", text: $targetLevel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
    
    // MARK: - Audio Monitoring
    
    private var audioMonitoringSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Audio Monitoring")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(isMonitoring ? "Stop Monitor" : "Start Monitor") {
                    isMonitoring ? stopMonitor() : startMonitor()
                }
            }
            
            VStack(spacing: 12) {
                SimpleAudioMeter(
                    title: "Input Level",
                    level: inputLevel,
                    isActive: isMonitoring && !recordingDevice.isEmpty
                )
                
                SimpleAudioMeter(
                    title: "Output Level",
                    level: outputLevel,
                    isActive: isMonitoring && !playbackDevice.isEmpty
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
    
    // MARK: - Processing Log
    
    private var processingLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing Log")
                .font(.title2)
                .fontWeight(.semibold)
            
            ScrollView {
                Text(viewModel.log)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 150)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Channel Mapping Sheet
    
    private var channelMappingSheet: some View {
        let pChannels = playbackDevices.first(where: { String($0.id) == playbackDevice })?.maxOutput ?? 2
        let rChannels = recordingDevices.first(where: { String($0.id) == recordingDevice })?.maxInput ?? 2
        let labels = fetchSpeakerLabels(layout: selectedLayout)
        
        return NavigationView {
            ChannelMappingView(
                playbackChannels: pChannels,
                recordingChannels: rChannels,
                speakerLabels: labels,
                playbackDevice: playbackDevice,
                channelMapping: $channelMapping,
                isPresented: $showMapping
            )
            .navigationTitle("Channel Mapping")
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    // MARK: - Helper Functions
    
    private func initializeView() {
        // Ensure default values are set before loading
        if channelBalance.isEmpty {
            channelBalance = "off"
        }
        
        loadLayoutsSync()
        loadDevicesSync()
        validatePaths()
        validateChannelCount()
    }
    
    private func loadLayoutsSync() {
        print("DEBUG: loadLayoutsSync called")
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.currentDirectoryURL = scriptsRoot
            
            print("DEBUG: scriptsRoot = \(scriptsRoot)")
            
            if let py = embeddedPythonURL {
                print("DEBUG: Using embedded Python: \(py)")
                process.executableURL = py
                process.arguments = [
                    "-c",
                    "import json,constants,sys; json.dump(sorted(constants.SPEAKER_LAYOUTS.keys()), sys.stdout)"
                ]
                process.environment = [
                    "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                    "PYTHONPATH": scriptsRoot.path
                ]
            } else {
                print("DEBUG: Using system Python")
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "python3",
                    "-c",
                    "import json,constants,sys; json.dump(sorted(constants.SPEAKER_LAYOUTS.keys()), sys.stdout)"
                ]
            }
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let dataString = String(data: data, encoding: .utf8) ?? "no data"
                print("DEBUG: Python output: \(dataString)")
                
                DispatchQueue.main.async {
                    if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                        print("DEBUG: Successfully parsed layouts: \(arr)")
                        
                        // CRITICAL: Force view update by updating layouts first
                        self.layouts = []  // Clear first
                        
                        // Use a slight delay to ensure SwiftUI processes the clear
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.layouts = arr  // Then set the new values
                            
                            // Ensure selectedLayout is valid
                            if !self.selectedLayout.isEmpty && !arr.contains(self.selectedLayout) {
                                print("DEBUG: selectedLayout '\(self.selectedLayout)' not in loaded layouts")
                                if let first = arr.first {
                                    self.selectedLayout = first
                                    print("DEBUG: Reset selectedLayout to: '\(first)'")
                                }
                            } else if self.selectedLayout.isEmpty && !arr.isEmpty {
                                if let first = arr.first {
                                    self.selectedLayout = first
                                    print("DEBUG: Set initial selectedLayout to: '\(first)'")
                                }
                            }
                            
                            print("DEBUG: Final state - layouts.count: \(self.layouts.count), selectedLayout: '\(self.selectedLayout)'")
                        }
                    } else {
                        print("DEBUG: Failed to parse JSON from: \(dataString)")
                        self.viewModel.log += "Failed to load layouts: \(dataString)\n"
                    }
                }
            } catch {
                print("DEBUG: Process execution failed: \(error)")
                DispatchQueue.main.async {
                    self.viewModel.log += "Process execution failed: \(error)\n"
                }
            }
        }
    }
    
    private func loadDevicesSync() {
        DispatchQueue.global(qos: .userInitiated).async {
#if os(macOS)
            let (caDevices, defaultInput, defaultOutput) = CoreAudioUtils.queryDevices()
            if !caDevices.isEmpty {
                let all = caDevices.map { d in
                    AudioDevice(id: Int(d.deviceID), name: d.name, maxOutput: d.maxOutput, maxInput: d.maxInput)
                }
                DispatchQueue.main.async {
                    self.playbackDevices = all.filter { $0.maxOutput > 0 }
                    self.recordingDevices = all.filter { $0.maxInput > 0 }
                    if self.playbackDevice.isEmpty, let def = defaultOutput,
                       let dev = self.playbackDevices.first(where: { $0.id == Int(def) }) {
                        self.playbackDevice = String(dev.id)
                    }
                    if self.recordingDevice.isEmpty, let def = defaultInput,
                       let dev = self.recordingDevices.first(where: { $0.id == Int(def) }) {
                        self.recordingDevice = String(dev.id)
                    }
                    if !self.playbackDevices.contains(where: { String($0.id) == self.playbackDevice }) {
                        self.playbackDevice = self.playbackDevices.first.map { String($0.id) } ?? ""
                    }
                    if !self.recordingDevices.contains(where: { String($0.id) == self.recordingDevice }) {
                        self.recordingDevice = self.recordingDevices.first.map { String($0.id) } ?? ""
                    }
                }
                return
            }
#endif
            // Fallback Python device detection...
            let process = Process()
            process.currentDirectoryURL = scriptsRoot
            if let py = embeddedPythonURL {
                process.executableURL = py
                process.arguments = [
                    "-c",
                    "import json, sounddevice as sd, sys; json.dump({'devices': sd.query_devices(), 'default': list(sd.default.device)}, sys.stdout)"
                ]
                process.environment = [
                    "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                    "PYTHONPATH": scriptsRoot.path
                ]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "python3",
                    "-c",
                    "import json, sounddevice as sd, sys; json.dump({'devices': sd.query_devices(), 'default': list(sd.default.device)}, sys.stdout)"
                ]
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let devs = obj["devices"] as? [[String: Any]]
            else {
                DispatchQueue.main.async {
                    self.viewModel.log += String(data: data, encoding: .utf8) ?? "Failed to load audio devices\n"
                }
                return
            }
            let defaults = (obj["default"] as? [Int]) ?? [-1, -1]
            let all = devs.enumerated().map { idx, d in
                AudioDevice(
                    id: idx,
                    name: (d["name"] as? String) ?? "Unknown",
                    maxOutput: d["max_output_channels"] as? Int ?? 0,
                    maxInput: d["max_input_channels"] as? Int ?? 0
                )
            }
            DispatchQueue.main.async {
                self.playbackDevices = all.filter { $0.maxOutput > 0 }
                self.recordingDevices = all.filter { $0.maxInput > 0 }
                if self.playbackDevice.isEmpty, defaults[1] >= 0,
                   let dev = self.playbackDevices.first(where: { $0.id == defaults[1] }) {
                    self.playbackDevice = String(dev.id)
                }
                if self.recordingDevice.isEmpty, defaults[0] >= 0,
                   let dev = self.recordingDevices.first(where: { $0.id == defaults[0] }) {
                    self.recordingDevice = String(dev.id)
                }
                if !self.playbackDevices.contains(where: { String($0.id) == self.playbackDevice }) {
                    self.playbackDevice = self.playbackDevices.first.map { String($0.id) } ?? ""
                }
                if !self.recordingDevices.contains(where: { String($0.id) == self.recordingDevice }) {
                    self.recordingDevice = self.recordingDevices.first.map { String($0.id) } ?? ""
                }
            }
        }
    }

    private func saveRecording() {
        guard let files = selectFilesPanel(startPath: measurementDir),
              !files.isEmpty,
              let path = saveDirectoryPanel(startPath: measurementDir) else {
            viewModel.logMessage("No measurement files found to save.\n")
            return
        }
        recordingVM.saveFiles(files: files,
                              measurementDir: measurementDir,
                              destination: path) { viewModel.logMessage($0) }
        measurementDir = path
        validatePaths()
    }

    func validatePaths() {
        testSignalValid = FileManager.default.fileExists(atPath: testSignal)
        recordingVM.validatePaths(measurementDir)
        validateChannelCount()
    }

    func validateChannelCount() {
        let spkCount = fetchSpeakerLabels(layout: selectedLayout).count
        let pChans = playbackDevices.first(where: { String($0.id) == playbackDevice })?.maxOutput ?? 0
        let rChans = recordingDevices.first(where: { String($0.id) == recordingDevice })?.maxInput ?? 0

        var warnings: [String] = []
        if pChans < spkCount && spkCount > 0 {
            warnings.append("Playback device only has \(pChans) channels while layout requires \(spkCount).")
        }
        if rChans < 2 {
            let suffix = rChans == 1 ? "" : "s"
            warnings.append("Recording device only has \(rChans) channel\(suffix); two are required.")
        }
        channelWarning = warnings.joined(separator: "\n")
    }

    // Include all your other existing functions: startMonitor, stopMonitor, loadDevices, loadLayouts, autoMapChannels, fetchSpeakerLabels
    // (Same as in your original SetupView - these don't need to change)
    
    func startMonitor() {
        stopMonitor()
        isMonitoring = true

        if !recordingDevice.isEmpty {
            let proc = Process()
            proc.currentDirectoryURL = scriptsRoot
            if let py = embeddedPythonURL {
                proc.executableURL = py
                proc.arguments = [scriptPath("level_meter.py"), "--device", recordingDevice]
                proc.environment = [
                    "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                    "PYTHONPATH": scriptsRoot.path
                ]
            } else {
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["python3", scriptPath("level_meter.py"), "--device", recordingDevice]
            }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                let vals = str.split(separator: "\n")
                if let last = vals.last, let db = Double(last) {
                    let value = max(0, min(1, (db + 60) / 60))
                    DispatchQueue.main.async { self.inputLevel = value }
                }
            }
            inputProcess = proc
            inputPipe = pipe
            try? proc.run()
        }

        if !playbackDevice.isEmpty {
            let proc = Process()
            proc.currentDirectoryURL = scriptsRoot
            if let py = embeddedPythonURL {
                proc.executableURL = py
                proc.arguments = [scriptPath("level_meter.py"), "--device", playbackDevice, "--loopback"]
                proc.environment = [
                    "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                    "PYTHONPATH": scriptsRoot.path
                ]
            } else {
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["python3", scriptPath("level_meter.py"), "--device", playbackDevice, "--loopback"]
            }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                let vals = str.split(separator: "\n")
                if let last = vals.last, let db = Double(last) {
                    let value = max(0, min(1, (db + 60) / 60))
                    DispatchQueue.main.async { self.outputLevel = value }
                }
            }
            outputProcess = proc
            outputPipe = pipe
            try? proc.run()
        }
    }

    func stopMonitor() {
        isMonitoring = false
        inputProcess?.terminate()
        outputProcess?.terminate()
        inputProcess = nil
        outputProcess = nil
        inputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe = nil
        outputPipe = nil
        inputLevel = 0
        outputLevel = 0
    }

    func loadDevices() {
        DispatchQueue.global(qos: .userInitiated).async {
#if os(macOS)
            let (caDevices, defaultInput, defaultOutput) = CoreAudioUtils.queryDevices()
            if !caDevices.isEmpty {
                let all = caDevices.map { d in
                    AudioDevice(id: Int(d.deviceID), name: d.name, maxOutput: d.maxOutput, maxInput: d.maxInput)
                }
                DispatchQueue.main.async {
                    self.playbackDevices = all.filter { $0.maxOutput > 0 }
                    self.recordingDevices = all.filter { $0.maxInput > 0 }
                    if self.playbackDevice.isEmpty, let def = defaultOutput,
                       let dev = self.playbackDevices.first(where: { $0.id == Int(def) }) {
                        self.playbackDevice = String(dev.id)
                    }
                    if self.recordingDevice.isEmpty, let def = defaultInput,
                       let dev = self.recordingDevices.first(where: { $0.id == Int(def) }) {
                        self.recordingDevice = String(dev.id)
                    }
                    if !self.playbackDevices.contains(where: { String($0.id) == self.playbackDevice }) {
                        self.playbackDevice = self.playbackDevices.first.map { String($0.id) } ?? ""
                    }
                    if !self.recordingDevices.contains(where: { String($0.id) == self.recordingDevice }) {
                        self.recordingDevice = self.recordingDevices.first.map { String($0.id) } ?? ""
                    }
                    self.validateChannelCount()
                }
                return
            }
#endif
            // Fallback Python device detection code...
            let process = Process()
            process.currentDirectoryURL = scriptsRoot
            if let py = embeddedPythonURL {
                process.executableURL = py
                process.arguments = [
                    "-c",
                    "import json, sounddevice as sd, sys; json.dump({'devices': sd.query_devices(), 'default': list(sd.default.device)}, sys.stdout)"
                ]
                process.environment = [
                    "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                    "PYTHONPATH": scriptsRoot.path
                ]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "python3",
                    "-c",
                    "import json, sounddevice as sd, sys; json.dump({'devices': sd.query_devices(), 'default': list(sd.default.device)}, sys.stdout)"
                ]
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let devs = obj["devices"] as? [[String: Any]]
            else {
                DispatchQueue.main.async {
                    self.viewModel.log += String(data: data, encoding: .utf8) ?? "Failed to load audio devices\n"
                }
                return
            }
            let defaults = (obj["default"] as? [Int]) ?? [-1, -1]
            let all = devs.enumerated().map { idx, d in
                AudioDevice(
                    id: idx,
                    name: (d["name"] as? String) ?? "Unknown",
                    maxOutput: d["max_output_channels"] as? Int ?? 0,
                    maxInput: d["max_input_channels"] as? Int ?? 0
                )
            }
            DispatchQueue.main.async {
                self.playbackDevices = all.filter { $0.maxOutput > 0 }
                self.recordingDevices = all.filter { $0.maxInput > 0 }
                if self.playbackDevice.isEmpty, defaults[1] >= 0,
                   let dev = self.playbackDevices.first(where: { $0.id == defaults[1] }) {
                    self.playbackDevice = String(dev.id)
                }
                if self.recordingDevice.isEmpty, defaults[0] >= 0,
                   let dev = self.recordingDevices.first(where: { $0.id == defaults[0] }) {
                    self.recordingDevice = String(dev.id)
                }
                if !self.playbackDevices.contains(where: { String($0.id) == self.playbackDevice }) {
                    self.playbackDevice = self.playbackDevices.first.map { String($0.id) } ?? ""
                }
                if !self.recordingDevices.contains(where: { String($0.id) == self.recordingDevice }) {
                    self.recordingDevice = self.recordingDevices.first.map { String($0.id) } ?? ""
                }
                self.validateChannelCount()
            }
        }
    }

    @MainActor
    func loadLayouts() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.currentDirectoryURL = scriptsRoot
                if let py = embeddedPythonURL {
                    process.executableURL = py
                    process.arguments = [
                        "-c",
                        "import json,constants,sys; json.dump(sorted(constants.SPEAKER_LAYOUTS.keys()), sys.stdout)"
                    ]
                    process.environment = [
                        "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                        "PYTHONPATH": scriptsRoot.path
                    ]
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [
                        "python3",
                        "-c",
                        "import json,constants,sys; json.dump(sorted(constants.SPEAKER_LAYOUTS.keys()), sys.stdout)"
                    ]
                }
                let pipe = Pipe()
                process.standardOutput = pipe
                try? process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                DispatchQueue.main.async {
                    if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                        self.layouts = arr
                        print("DEBUG: Loaded layouts: \(arr)")
                        print("DEBUG: Current selectedLayout: '\(self.selectedLayout)'")
                        
                        // Only update selectedLayout if it's empty or invalid
                        if self.selectedLayout.isEmpty {
                            if let first = arr.first {
                                self.selectedLayout = first
                                print("DEBUG: Set initial selectedLayout to: '\(first)'")
                            }
                        } else if !arr.contains(self.selectedLayout) {
                            print("DEBUG: selectedLayout '\(self.selectedLayout)' not found in loaded layouts")
                            if let first = arr.first {
                                self.selectedLayout = first
                                print("DEBUG: Reset selectedLayout to: '\(first)'")
                            }
                        }
                    } else {
                        self.viewModel.log += String(data: data, encoding: .utf8) ?? "Failed to load layouts\n"
                        print("DEBUG: Failed to load layouts: \(String(data: data, encoding: .utf8) ?? "no data")")
                    }
                    continuation.resume()
                }
            }
        }
        
        // Validate after layouts are loaded - but don't call validateChannelCount here
        // to avoid the circular dependency
    }

    func autoMapChannels() {
        guard
            let pDev = playbackDevices.first(where: { String($0.id) == playbackDevice }),
            let rDev = recordingDevices.first(where: { String($0.id) == recordingDevice })
        else { return }
        let spkCount = fetchSpeakerLabels(layout: selectedLayout).count
        if spkCount == 0 {
            viewModel.log += "Unable to auto map channels: no speaker labels for layout \(selectedLayout).\n"
            return
        }
        channelMapping["output_channels"] = Array(0..<min(pDev.maxOutput, spkCount))
        channelMapping["input_channels"] = Array(0..<min(rDev.maxInput, 2))
    }

    func fetchSpeakerLabels(layout: String) -> [String] {
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        if let py = embeddedPythonURL {
            process.executableURL = py
            process.arguments = [
                "-c",
                "import json,constants,sys; print(json.dumps([c for g in constants.SPEAKER_LAYOUTS.get('" + layout + "', []) for c in g]))"
            ]
            process.environment = [
                "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                "PYTHONPATH": scriptsRoot.path
            ]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                "-c",
                "import json,constants,sys; print(json.dumps([c for g in constants.SPEAKER_LAYOUTS.get('" + layout + "', []) for c in g]))"
            ]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr
        }
        return []
    }
}

// MARK: - Simplified Supporting Components

struct SimpleConfigRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
        }
    }
}

struct SimpleActionCard: View {
    let title: String
    let icon: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isEnabled ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SimpleAudioMeter: View {
    let title: String
    let level: Double
    let isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Circle()
                    .fill(isActive ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(meterColor(for: level))
                        .frame(width: geometry.size.width * level, height: 4)
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
            .frame(height: 4)
        }
    }
    
    private func meterColor(for level: Double) -> Color {
        switch level {
        case 0.8...1.0: return .red
        case 0.6..<0.8: return .orange
        default: return .green
        }
    }
}

#endif
