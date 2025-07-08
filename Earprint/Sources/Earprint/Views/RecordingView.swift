#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Recording View
struct RecordingView: View {
    @ObservedObject var processingVM: ProcessingViewModel
    @ObservedObject var recordingVM: RecordingViewModel
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    @ObservedObject var configurationVM: ConfigurationViewModel
    
    // MARK: - Recording Settings
    @State private var measurementDir: String = ""
    @State private var testSignalPath: String = ""
    @State private var recordingType: RecordingType = .measurement
    @State private var outputFileName: String = ""
    @State private var useCustomName: Bool = false
    
    // MARK: - UI State
    @State private var showingDirectoryPicker = false
    @State private var showingTestSignalPicker = false
    @State private var showingRecordingResults = false
    @State private var recordingResultsURL: URL?
    
    enum RecordingType: String, CaseIterable {
        case measurement = "Measurement Recording"
        case headphone = "Headphone EQ"
        case roomResponse = "Room Response"
        case testSweep = "Test Sweep"
        
        var defaultFileName: String {
            switch self {
            case .measurement: return "measurement"
            case .headphone: return "headphones"
            case .roomResponse: return "room"
            case .testSweep: return "test_sweep"
            }
        }
        
        var description: String {
            switch self {
            case .measurement: return "Record binaural impulse response measurements"
            case .headphone: return "Record headphone compensation signal"
            case .roomResponse: return "Record room acoustic response"
            case .testSweep: return "Record test sweep for calibration"
            }
        }
        
        var icon: String {
            switch self {
            case .measurement: return "waveform.circle"
            case .headphone: return "headphones"
            case .roomResponse: return "speaker.wave.3"
            case .testSweep: return "tuningfork"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Section
            RecordingHeaderView(
                recordingType: $recordingType,
                isRecording: processingVM.isRunning
            )
            
            Divider()
            
            // Main Content
            ScrollView {
                VStack(spacing: 24) {
                    // Recording Configuration
                    RecordingConfigurationSection(
                        measurementDir: $measurementDir,
                        testSignalPath: $testSignalPath,
                        outputFileName: $outputFileName,
                        useCustomName: $useCustomName,
                        recordingType: recordingType,
                        showingDirectoryPicker: $showingDirectoryPicker,
                        showingTestSignalPicker: $showingTestSignalPicker,
                        configurationVM: configurationVM
                    )
                    
                    // Audio Device Status
                    AudioDeviceStatusSection(audioDeviceVM: audioDeviceVM)
                    
                    // Recording Controls
                    RecordingControlsSection(
                        processingVM: processingVM,
                        recordingVM: recordingVM,
                        measurementDir: measurementDir,
                        testSignalPath: testSignalPath,
                        outputFileName: outputFileName,
                        useCustomName: useCustomName,
                        recordingType: recordingType,
                        audioDeviceVM: audioDeviceVM,
                        resultURL: $recordingResultsURL,
                        showingResults: $showingRecordingResults
                    )
                    
                    // Progress and Status
                    if processingVM.isRunning {
                        RecordingProgressSection(processingVM: processingVM)
                    }
                    
                    // Recent Recordings
                    RecentRecordingsSection(
                        recordingVM: recordingVM,
                        measurementDir: measurementDir
                    )
                }
                .padding()
            }
            
            Divider()
            
            // Bottom Status Bar
            RecordingStatusBar(
                processingVM: processingVM,
                audioDeviceVM: audioDeviceVM,
                recordingVM: recordingVM
            )
        }
        .navigationTitle("Recording")
        .onAppear {
            loadDefaults()
            refreshRecordings()
        }
        .onChange(of: measurementDir) { _ in
            recordingVM.validatePaths(measurementDir)
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectorySelection(result)
        }
        .fileImporter(
            isPresented: $showingTestSignalPicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleTestSignalSelection(result)
        }
        .sheet(isPresented: $showingRecordingResults) {
            if let url = recordingResultsURL {
                RecordingResultsSheet(recordingURL: url, recordingVM: recordingVM)
            }
        }
    }
    
    // MARK: - Helper Methods
    private func loadDefaults() {
        measurementDir = configurationVM.appConfiguration.defaultMeasurementDir
        testSignalPath = configurationVM.appConfiguration.defaultTestSignal
        
        if measurementDir.isEmpty {
            measurementDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Recordings").path ?? ""
        }
    }
    
    private func refreshRecordings() {
        if !measurementDir.isEmpty {
            recordingVM.validatePaths(measurementDir)
        }
    }
    
    private func handleDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                measurementDir = url.path
                configurationVM.addRecentProject(url.path)
            }
        case .failure(let error):
            // Handle error - could show alert
            print("Directory selection error: \(error)")
        }
    }
    
    private func handleTestSignalSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                testSignalPath = url.path
            }
        case .failure(let error):
            // Handle error - could show alert
            print("Test signal selection error: \(error)")
        }
    }
}

// MARK: - Recording Header View
struct RecordingHeaderView: View {
    @Binding var recordingType: RecordingView.RecordingType
    let isRecording: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: recordingType.icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text(recordingType.rawValue)
                        .font(.headline)
                    Text(recordingType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isRecording ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 1.0).repeatForever(), value: isRecording)
                        
                        Text("Recording")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !isRecording {
                Picker("Recording Type", selection: $recordingType) {
                    ForEach(RecordingView.RecordingType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
}

// MARK: - Recording Configuration Section
struct RecordingConfigurationSection: View {
    @Binding var measurementDir: String
    @Binding var testSignalPath: String
    @Binding var outputFileName: String
    @Binding var useCustomName: Bool
    let recordingType: RecordingView.RecordingType
    @Binding var showingDirectoryPicker: Bool
    @Binding var showingTestSignalPicker: Bool
    @ObservedObject var configurationVM: ConfigurationViewModel
    
    var body: some View {
        GroupBox("Recording Configuration") {
            VStack(spacing: 16) {
                // Measurement Directory
                VStack(alignment: .leading, spacing: 8) {
                    Label("Output Directory", systemImage: "folder")
                        .font(.headline)
                    
                    HStack {
                        TextField("Select output directory...", text: $measurementDir)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse") {
                            showingDirectoryPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if !measurementDir.isEmpty && !FileManager.default.fileExists(atPath: measurementDir) {
                        Label("Directory does not exist", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                Divider()
                
                // Test Signal
                VStack(alignment: .leading, spacing: 8) {
                    Label("Test Signal", systemImage: "waveform")
                        .font(.headline)
                    
                    HStack {
                        TextField("Select test signal file...", text: $testSignalPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse") {
                            showingTestSignalPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if !testSignalPath.isEmpty && !FileManager.default.fileExists(atPath: testSignalPath) {
                        Label("Test signal file not found", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                Divider()
                
                // Output File Name
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Output File", systemImage: "doc")
                            .font(.headline)
                        
                        Spacer()
                        
                        Toggle("Custom name", isOn: $useCustomName)
                            .toggleStyle(.switch)
                    }
                    
                    if useCustomName {
                        TextField("Enter filename...", text: $outputFileName)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text("Will use: \(recordingType.defaultFileName).wav")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Audio Device Status Section
struct AudioDeviceStatusSection: View {
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    
    var body: some View {
        GroupBox("Audio Device Status") {
            VStack(spacing: 12) {
                // Input Device
                HStack {
                    Image(systemName: "mic")
                        .foregroundColor(audioDeviceVM.selectedInputDevice != nil ? .green : .red)
                    
                    VStack(alignment: .leading) {
                        Text("Input Device")
                            .font(.headline)
                        Text(audioDeviceVM.selectedInputDevice?.name ?? "No device selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let device = audioDeviceVM.selectedInputDevice {
                        Text("\(device.maxInputChannels) ch")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Divider()
                
                // Output Device
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(audioDeviceVM.selectedOutputDevice != nil ? .green : .red)
                    
                    VStack(alignment: .leading) {
                        Text("Output Device")
                            .font(.headline)
                        Text(audioDeviceVM.selectedOutputDevice?.name ?? "No device selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let device = audioDeviceVM.selectedOutputDevice {
                        Text("\(device.maxOutputChannels) ch")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                // Device Warnings
                if !audioDeviceVM.deviceWarnings.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(audioDeviceVM.deviceWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Recording Controls Section
struct RecordingControlsSection: View {
    @ObservedObject var processingVM: ProcessingViewModel
    @ObservedObject var recordingVM: RecordingViewModel
    let measurementDir: String
    let testSignalPath: String
    let outputFileName: String
    let useCustomName: Bool
    let recordingType: RecordingView.RecordingType
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    @Binding var resultURL: URL?
    @Binding var showingResults: Bool
    
    private var canStartRecording: Bool {
        !measurementDir.isEmpty &&
        !testSignalPath.isEmpty &&
        audioDeviceVM.selectedInputDevice != nil &&
        audioDeviceVM.selectedOutputDevice != nil &&
        !processingVM.isRunning
    }
    
    private var finalOutputPath: String {
        if useCustomName && !outputFileName.isEmpty {
            return URL(fileURLWithPath: measurementDir).appendingPathComponent("\(outputFileName).wav").path
        } else {
            return URL(fileURLWithPath: measurementDir).appendingPathComponent("\(recordingType.defaultFileName).wav").path
        }
    }
    
    var body: some View {
        GroupBox("Recording Controls") {
            VStack(spacing: 16) {
                // Recording Button
                VStack(spacing: 8) {
                    Button(action: startRecording) {
                        HStack {
                            Image(systemName: processingVM.isRunning ? "stop.circle.fill" : "record.circle")
                                .font(.title2)
                            
                            Text(processingVM.isRunning ? "Stop Recording" : "Start Recording")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(processingVM.isRunning ? Color.red : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(processingVM.isRunning ? false : !canStartRecording)
                    
                    if !canStartRecording && !processingVM.isRunning {
                        Text("Configure audio devices and paths in Settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Output Preview
                if canStartRecording || processingVM.isRunning {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recording will be saved to:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(finalOutputPath)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding()
        }
    }
    
    private func startRecording() {
        if processingVM.isRunning {
            processingVM.cancel()
        } else {
            guard let inputDevice = audioDeviceVM.selectedInputDevice,
                  let outputDevice = audioDeviceVM.selectedOutputDevice else { return }
            
            // Create configuration for recording
            let configuration = RecordingConfiguration(
                measurementDir: measurementDir,
                testSignal: testSignalPath,
                playbackDevice: String(outputDevice.id),
                recordingDevice: String(inputDevice.id),
                outputFile: finalOutputPath
            )
            
            // Start recording based on type
            switch recordingType {
            case .measurement:
                processingVM.record(configuration: configuration)
            case .headphone:
                processingVM.recordHeadphoneEQ(configuration: configuration)
            case .roomResponse:
                processingVM.recordRoomResponse(configuration: configuration)
            case .testSweep:
                processingVM.record(configuration: configuration)
            }
            
            // Set up completion handling
            resultURL = URL(fileURLWithPath: finalOutputPath)
        }
    }
}

// MARK: - Recording Progress Section
struct RecordingProgressSection: View {
    @ObservedObject var processingVM: ProcessingViewModel
    
    var body: some View {
        GroupBox("Recording Progress") {
            VStack(spacing: 12) {
                if let progress = processingVM.progress {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                        }
                        .font(.caption)
                        
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                } else {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        
                        Text("Recording in progress...")
                            .font(.caption)
                    }
                }
                
                if let remainingTime = processingVM.remainingTime {
                    Text("Estimated time remaining: \(Int(remainingTime))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

// MARK: - Recent Recordings Section
struct RecentRecordingsSection: View {
    @ObservedObject var recordingVM: RecordingViewModel
    let measurementDir: String
    
    var body: some View {
        GroupBox("Recent Recordings") {
            VStack(spacing: 8) {
                if recordingVM.recordings.isEmpty {
                    Text("No recordings found")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding()
                } else {
                    ForEach(recordingVM.recordings.prefix(5)) { recording in
                        RecentRecordingRow(recording: recording, recordingVM: recordingVM)
                    }
                    
                    if recordingVM.recordings.count > 5 {
                        Text("... and \(recordingVM.recordings.count - 5) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Recent Recording Row
struct RecentRecordingRow: View {
    let recording: RecordingInfo
    @ObservedObject var recordingVM: RecordingViewModel
    
    var body: some View {
        HStack {
            Image(systemName: recordingVM.getRecordingIcon(recording))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.name)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack {
                    Text(recordingVM.getRecordingAge(recording))
                    Text("•")
                    Text(recordingVM.getRecordingSize(recording))
                    Text("•")
                    Text(recordingVM.getMeasurementType(recording))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Show") {
                // Could open file location or show details
                NSWorkspace.shared.selectFile(recording.path, inFileViewerRootedAtPath: "")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recording Status Bar
struct RecordingStatusBar: View {
    @ObservedObject var processingVM: ProcessingViewModel
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    @ObservedObject var recordingVM: RecordingViewModel
    
    var body: some View {
        HStack {
            // Processing Status
            HStack(spacing: 8) {
                Circle()
                    .fill(processingVM.isRunning ? .green : .gray)
                    .frame(width: 8, height: 8)
                
                Text(processingVM.isRunning ? "Recording" : "Ready")
                    .font(.caption)
            }
            
            Spacer()
            
            // Audio Device Status
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "mic")
                        .foregroundColor(audioDeviceVM.selectedInputDevice != nil ? .green : .red)
                    Text("Input")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(audioDeviceVM.selectedOutputDevice != nil ? .green : .red)
                    Text("Output")
                        .font(.caption)
                }
            }
            
            Spacer()
            
            // File Count
            Text("\(recordingVM.recordings.count) files")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }
}

// MARK: - Recording Results Sheet
struct RecordingResultsSheet: View {
    let recordingURL: URL
    @ObservedObject var recordingVM: RecordingViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Recording Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("File saved to:")
                        .font(.headline)
                    
                    Text(recordingURL.path)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                HStack(spacing: 16) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(recordingURL.path, inFileViewerRootedAtPath: "")
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Recording Complete")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#else
// Non-macOS stub implementation
struct RecordingView: View {
    var body: some View {
        Text("Recording not available on this platform")
    }
}
#endif
