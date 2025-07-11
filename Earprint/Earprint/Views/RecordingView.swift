#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Recording View
struct RecordingView: View {
    @ObservedObject var processingVM: ProcessingViewModel
    @ObservedObject var recordingVM: RecordingViewModel
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    @ObservedObject var configurationVM: ConfigurationViewModel
    @EnvironmentObject var workspaceManager: WorkspaceManager
    
    // MARK: - Recording Settings
    @State private var testSignalPath: String = ""
    @State private var recordingType: RecordingType = .measurement
    @State private var selectedLayoutName: String = "2.0"
    @State private var availableLayouts: [String: SpeakerLayoutInfo] = [:]
    @State private var outputFileName: String = ""
    @State private var useCustomName: Bool = false
    
    // MARK: - UI State
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
    
    private var canStartRecording: Bool {
        !testSignalPath.isEmpty &&
        audioDeviceVM.selectedInputDevice != nil &&
        audioDeviceVM.selectedOutputDevice != nil &&
        !recordingVM.isRecording  // Changed from processingVM.isRunning
    }
    
    private var currentLayout: SpeakerLayoutInfo? {
        availableLayouts[selectedLayoutName]
    }
    
    private var finalOutputPath: String {
        // For measurement recordings, use speaker layout-specific naming
        if recordingType == .measurement, let layout = currentLayout {
            let groups = layout.groups
            if groups.count == 1 {
                // Single file recording
                if useCustomName && !outputFileName.isEmpty {
                    return workspaceManager.currentWorkspace.appendingPathComponent("\(outputFileName).wav").path
                } else {
                    return workspaceManager.currentWorkspace.appendingPathComponent(groups[0].filename).path
                }
            } else {
                // Multi-file recording - return first file path for display
                return workspaceManager.currentWorkspace.appendingPathComponent(groups[0].filename).path
            }
        } else {
            // Other recording types use traditional naming
            if useCustomName && !outputFileName.isEmpty {
                return workspaceManager.currentWorkspace.appendingPathComponent("\(outputFileName).wav").path
            } else {
                return workspaceManager.currentWorkspace.appendingPathComponent("\(recordingType.defaultFileName).wav").path
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Section with Recording Button
            RecordingHeaderView(
                recordingType: $recordingType,
                selectedLayoutName: $selectedLayoutName,
                availableLayouts: availableLayouts,
                isRecording: processingVM.isRunning,
                canStartRecording: canStartRecording,
                finalOutputPath: finalOutputPath,
                currentWorkspace: workspaceManager.workspaceName,
                startRecordingAction: startRecording,
                audioDeviceVM: audioDeviceVM
            )
            
            Divider()
            
            // Main Content
            ScrollView {
                VStack(spacing: 24) {
                    // Workspace Info
                    WorkspaceInfoSection(workspaceManager: workspaceManager)
                    
                    // Recording Configuration
                    RecordingConfigurationSection(
                        testSignalPath: $testSignalPath,
                        outputFileName: $outputFileName,
                        useCustomName: $useCustomName,
                        recordingType: recordingType,
                        currentLayout: currentLayout,
                        showingTestSignalPicker: $showingTestSignalPicker,
                        workspaceManager: workspaceManager
                    )
                    
                    // Progress and Status
                    if processingVM.isRunning {
                        RecordingProgressSection(processingVM: processingVM)
                    }
                    
                    // Recent Recordings
                    RecentRecordingsSection(
                        recordingVM: recordingVM,
                        workspaceManager: workspaceManager
                    )
                }
                .padding()
            }
            
            Divider()
            
            // Bottom Status Bar
            RecordingStatusBar(
                processingVM: processingVM,
                audioDeviceVM: audioDeviceVM,
                recordingVM: recordingVM,
                workspaceManager: workspaceManager
            )
        }
        .navigationTitle("Recording")
        .onAppear {
            loadDefaults()
            loadSpeakerLayouts()
            refreshRecordings()
        }
        .onChange(of: workspaceManager.currentWorkspace) { _ in
            refreshRecordings()
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
        // Load default test signal from Scripts/data directory
        if let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") {
            let defaultTestSignalPath = scriptsRoot.appendingPathComponent("data/sweep-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav")
            
            if FileManager.default.fileExists(atPath: defaultTestSignalPath.path) {
                testSignalPath = defaultTestSignalPath.path
                print("✅ Loaded default test signal: \(defaultTestSignalPath.path)")
            } else {
                print("⚠️ Default test signal not found at: \(defaultTestSignalPath.path)")
                
                // Fallback to configuration if available
                if !configurationVM.appConfiguration.defaultTestSignal.isEmpty {
                    testSignalPath = configurationVM.appConfiguration.defaultTestSignal
                    print("✅ Using test signal from configuration: \(testSignalPath)")
                }
            }
        } else {
            print("❌ Scripts directory not found in bundle")
            
            // Fallback to configuration
            if !configurationVM.appConfiguration.defaultTestSignal.isEmpty {
                testSignalPath = configurationVM.appConfiguration.defaultTestSignal
                print("✅ Using test signal from configuration: \(testSignalPath)")
            }
        }
    }
    
    private func loadSpeakerLayouts() {
        // Call RecordingViewModel to get speaker layouts from Python backend
        recordingVM.getSpeakerLayouts { vmLayouts in
            DispatchQueue.main.async {
                // Convert RecordingViewModel types to local types
                var convertedLayouts: [String: SpeakerLayoutInfo] = [:]
                
                for (key, vmLayout) in vmLayouts {
                    let convertedGroups = vmLayout.groups.map { vmGroup in
                        RecordingGroup(name: vmGroup.name, speakers: vmGroup.speakers)
                    }
                    
                    let convertedLayout = SpeakerLayoutInfo(
                        name: vmLayout.name,
                        displayName: vmLayout.displayName,
                        groups: convertedGroups,
                        icon: vmLayout.icon
                    )
                    
                    convertedLayouts[key] = convertedLayout
                }
                
                self.availableLayouts = convertedLayouts
                if self.selectedLayoutName.isEmpty && !convertedLayouts.isEmpty {
                self.selectedLayoutName = convertedLayouts.keys.sorted().first ?? "2.0"
                }
                self.validateCurrentLayout()
            }
        }
    }
    
    private func refreshRecordings() {
        recordingVM.validatePaths(workspaceManager.currentWorkspace.path)
    }
    
    private func handleTestSignalSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                testSignalPath = url.path
            }
        case .failure(let error):
            print("Test signal selection error: \(error)")
        }
    }
    
    // MARK: - Validation method for RecordingView

    private func validateCurrentLayout() {
        guard let layout = currentLayout else { return }
        
        // Convert to ViewModel layout format
        let vmGroups = layout.groups.map { localGroup in
            RecordingGroup(name: localGroup.name, speakers: localGroup.speakers)
        }
        
        let vmLayout = SpeakerLayoutInfo(
            name: layout.name,
            displayName: layout.displayName,
            groups: vmGroups,
            icon: layout.icon
        )
        
        // Check for missing test signals
        let missingSignals = recordingVM.validateTestSignalsForLayout(vmLayout)
        
        if !missingSignals.isEmpty {
            print("⚠️ Missing test signals for groups: \(missingSignals.joined(separator: ", "))")
            // You could show this warning in the UI if needed
        }
    }

    private func startRecording() {
        if recordingVM.isRecording {
            // Stop recording
            recordingVM.stopRecording()
            return
        } else {
            guard let inputDevice = audioDeviceVM.selectedInputDevice,
                  let outputDevice = audioDeviceVM.selectedOutputDevice else { return }
            
            // For measurement recordings, use ViewModel's smart selection
            if recordingType == .measurement, let layout = currentLayout {
                // Convert local layout to ViewModel layout
                let vmGroups = layout.groups.map { localGroup in
                    RecordingGroup(name: localGroup.name, speakers: localGroup.speakers)
                }
                
                let vmLayout = SpeakerLayoutInfo(
                    name: layout.name,
                    displayName: layout.displayName,
                    groups: vmGroups,
                    icon: layout.icon
                )
                
                // Create base configuration
                let configuration = RecordingConfiguration(
                    measurementDir: workspaceManager.currentWorkspace.path,
                    testSignal: testSignalPath, // This will be overridden by smart selection
                    playbackDevice: String(outputDevice.id),
                    recordingDevice: String(inputDevice.id),
                    outputFile: "", // This will be set by the ViewModel
                    speakerLayout: layout.name,
                    recordingGroup: nil, // This will be set by the ViewModel
                    outputChannels: [0, 1], // This will be overridden by smart selection
                    inputChannels: [0, 1]
                )
                
                // Use ViewModel's smart recording method
                recordingVM.startRecordingWithLayout(
                    configuration: configuration,
                    layout: vmLayout
                )
                
                // Set results URL for the first group
                if let firstGroup = layout.groups.first {
                    recordingResultsURL = workspaceManager.currentWorkspace.appendingPathComponent(firstGroup.filename)
                }
                
                // TODO: Implement sequential recording for multi-group layouts
                if layout.groups.count > 1 {
                    print("⚠️ Multi-group recording not yet implemented. Recording first group only.")
                }
                
            } else {
                // Traditional single-file recording for other types
                let configuration = RecordingConfiguration(
                    measurementDir: workspaceManager.currentWorkspace.path,
                    testSignal: testSignalPath,
                    playbackDevice: String(outputDevice.id),
                    recordingDevice: String(inputDevice.id),
                    outputFile: finalOutputPath,
                    speakerLayout: nil,
                    recordingGroup: nil,
                    outputChannels: [0, 1],
                    inputChannels: [0, 1]
                )
                
                // Start recording using standard method
                recordingVM.startRecording(with: configuration)
                recordingResultsURL = URL(fileURLWithPath: finalOutputPath)
            }
        }
    }
}

// MARK: - Workspace Info Section
struct WorkspaceInfoSection: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    
    var body: some View {
        GroupBox("Current Workspace") {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    
                    VStack(alignment: .leading) {
                        Text(workspaceManager.workspaceName)
                            .font(.headline)
                        
                        Text("Recordings will be saved to this workspace")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        let stats = workspaceManager.getWorkspaceStats()
                        
                        Text("\(stats.audioFiles) audio files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(stats.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspaceManager.currentWorkspace.path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    //Text(workspaceManager.currentWorkspace.path)
                    //    .font(.system(.caption2, design: .monospaced))
                    //    .foregroundColor(.secondary)
                    //    .lineLimit(1)
                    //    .truncationMode(.middle)
                }
            }
            .padding()
        }
    }
}

// MARK: - Recording Header View
struct RecordingHeaderView: View {
    @Binding var recordingType: RecordingView.RecordingType
    @Binding var selectedLayoutName: String
    let availableLayouts: [String: SpeakerLayoutInfo]
    let isRecording: Bool
    let canStartRecording: Bool
    let finalOutputPath: String
    let currentWorkspace: String
    let startRecordingAction: () -> Void
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    
    private var currentLayout: SpeakerLayoutInfo? {
        availableLayouts[selectedLayoutName]
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Type Selection and Info
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
                
                // Audio Device Status Indicators
                HStack(spacing: 12) {
                    // Input Device Indicator
                    HStack(spacing: 4) {
                        Image(systemName: "mic")
                            .foregroundColor(audioDeviceVM.selectedInputDevice != nil ? .green : .red)
                            .font(.caption)
                        
                        if let device = audioDeviceVM.selectedInputDevice {
                            Text(device.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 80)
                        } else {
                            Text("No Input")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Output Device Indicator
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundColor(audioDeviceVM.selectedOutputDevice != nil ? .green : .red)
                            .font(.caption)
                        
                        if let device = audioDeviceVM.selectedOutputDevice {
                            Text(device.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 80)
                        } else {
                            Text("No Output")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
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
            
            // Recording Type and Layout Pickers (only when not recording)
            if !isRecording {
                VStack(spacing: 12) {
                    Picker("Recording Type", selection: $recordingType) {
                        ForEach(RecordingView.RecordingType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Show speaker layout picker only for measurement recordings
                    if recordingType == .measurement && !availableLayouts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "speaker.wave.3")
                                    .foregroundColor(.accentColor)
                                Text("Speaker Layout")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Picker("Speaker Layout", selection: $selectedLayoutName) {
                                ForEach(availableLayouts.keys.sorted(), id: \.self) { layoutName in
                                    if let layout = availableLayouts[layoutName] {
                                        Label(layout.displayName, systemImage: layout.icon)
                                            .tag(layoutName)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            
                            // Show expected recording files
                            if let layout = currentLayout, layout.groups.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Recording sequence:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), alignment: .leading, spacing: 4) {
                                        ForEach(Array(layout.groups.enumerated()), id: \.offset) { index, group in
                                            Text(group.filename)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            
            // Recording Button
            VStack(spacing: 8) {
                Button(action: startRecordingAction) {
                    HStack {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.title2)
                        
                        Text(isRecording ? "Stop Recording" : "Start Recording")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRecording ? Color.red : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isRecording ? false : !canStartRecording)
                
                if !canStartRecording && !isRecording {
                    Text("Configure audio devices and test signal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Output Preview (when ready or recording)
                if canStartRecording || isRecording {
                    VStack(alignment: .leading, spacing: 4) {
                        if recordingType == .measurement, let layout = currentLayout {
                            if layout.groups.count > 1 {
                                Text("Multiple files will be created for this layout:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ForEach(Array(layout.groups.enumerated()), id: \.offset) { index, group in
                                    Text(group.filename)
                                        .font(.system(.caption2, design: .monospaced))
                                        .padding(4)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            } else {
                                Text("Recording will be saved as:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(finalOutputPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        } else {
                            Text("Recording will be saved to workspace:")
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
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
}

// MARK: - Recording Configuration Section
struct RecordingConfigurationSection: View {
    @Binding var testSignalPath: String
    @Binding var outputFileName: String
    @Binding var useCustomName: Bool
    let recordingType: RecordingView.RecordingType
    let currentLayout: SpeakerLayoutInfo?
    @Binding var showingTestSignalPicker: Bool
    @ObservedObject var workspaceManager: WorkspaceManager
    
    var body: some View {
        GroupBox("Recording Configuration") {
            VStack(spacing: 16) {
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
                        
                        // Remove test signals menu for now - implement when WorkspaceManager has this property
                        // if !workspaceManager.testSignals.isEmpty {
                        //     Menu("Presets") {
                        //         ForEach(workspaceManager.testSignals) { signal in
                        //             Button(signal.name) {
                        //                 if let path = workspaceManager.copyTestSignalToWorkspace(signal) {
                        //                     testSignalPath = path
                        //                 }
                        //             }
                        //         }
                        //     }
                        //     .buttonStyle(.bordered)
                        // }
                    }
                    
                    if !testSignalPath.isEmpty {
                        if FileManager.default.fileExists(atPath: testSignalPath) {
                            Label("Test signal ready", systemImage: "checkmark.circle")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Label("Test signal file not found", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
                
                Divider()
                
                // Output File Name
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Output File", systemImage: "doc")
                            .font(.headline)
                        
                        Spacer()
                        
                        // Only show custom name toggle for single-file recordings
                        if recordingType != .measurement || (currentLayout?.groups.count ?? 0) <= 1 {
                            Toggle("Custom name", isOn: $useCustomName)
                                .toggleStyle(.switch)
                        }
                    }
                    
                    if recordingType == .measurement, let layout = currentLayout {
                        if layout.groups.count > 1 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Files will be named according to speaker layout:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ForEach(Array(layout.groups.enumerated()), id: \.offset) { index, group in
                                    Text("• \(group.filename)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else if useCustomName {
                            TextField("Enter filename...", text: $outputFileName)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text("Will use: \(layout.groups.first?.filename ?? "measurement.wav")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
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
            }
            .padding()
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
    @ObservedObject var workspaceManager: WorkspaceManager
    
    var body: some View {
        GroupBox("Recent Recordings") {
            VStack(spacing: 8) {
                if recordingVM.recordings.isEmpty {
                    VStack(spacing: 8) {
                        Text("No recordings in this workspace")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text("Start recording to create audio files")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
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
    @ObservedObject var workspaceManager: WorkspaceManager
    
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
            
            // Workspace Info
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .foregroundColor(.accentColor)
                Text(workspaceManager.workspaceName)
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
                    Text("File saved to workspace:")
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
