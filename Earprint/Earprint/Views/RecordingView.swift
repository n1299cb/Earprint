#if canImport(SwiftUI)
import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - Recording View
struct RecordingView: View {
    @ObservedObject var processingVM: ProcessingViewModel
    @ObservedObject var recordingVM: RecordingViewModel
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    @ObservedObject var configurationVM: ConfigurationViewModel
    @StateObject private var layoutManager = LayoutManager.shared
    @EnvironmentObject var workspaceManager: WorkspaceManager
    
    // MARK: - Recording Settings
    @State private var testSignalPath: String = ""
    @State private var recordingType: RecordingType = .measurement
    @State private var outputFileName: String = ""
    @State private var useCustomName: Bool = false
    
    // MARK: - UI State
    @State private var showingTestSignalPicker = false
    @State private var showingRecordingResults = false
    @State private var recordingResultsURL: URL?
    
    private var canStartRecording: Bool {
        !testSignalPath.isEmpty &&
        audioDeviceVM.selectedInputDevice != nil &&
        audioDeviceVM.selectedOutputDevice != nil &&
        !recordingVM.isRecording
    }
    
    private var currentLayout: SpeakerLayout? {
        return layoutManager.getCurrentLayout()
    }
    
    private var finalOutputPath: String {
        // For measurement recordings, use speaker layout-specific naming
        if recordingType == .measurement, let layout = layoutManager.getCurrentLayout() {
            let groups = layout.groups
            if groups.count == 1 {
                // Single file recording - use speaker labels joined by commas
                let firstGroup = groups[0]
                let fileName = "\(firstGroup.speakers.joined(separator: ",")).wav"
                
                if useCustomName && !outputFileName.isEmpty {
                    return workspaceManager.currentWorkspace.appendingPathComponent("\(outputFileName).wav").path
                } else {
                    return workspaceManager.currentWorkspace.appendingPathComponent(fileName).path
                }
            } else {
                // Multi-file recording - return first file path for display
                let firstGroup = groups[0]
                let fileName = "\(firstGroup.speakers.joined(separator: ",")).wav"
                return workspaceManager.currentWorkspace.appendingPathComponent(fileName).path
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
                selectedLayoutName: $layoutManager.selectedLayoutName,
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
            layoutManager.refreshLayouts()
            refreshRecordings()
        }
        .onChange(of: workspaceManager.currentWorkspace) { _ in
            refreshRecordings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .layoutChanged)) { _ in
                validateCurrentLayout()
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
        guard let layout = layoutManager.getCurrentLayout() else { return }
        
        // Use the updated validation method that expects SpeakerLayout
        let missingSignals = recordingVM.validateTestSignalsForLayout(layout)
        if !missingSignals.isEmpty {
            print("⚠️ Missing test signals for groups: \(missingSignals.joined(separator: ", "))")
        }
        
        // Validate device compatibility
        if let outputDevice = audioDeviceVM.selectedOutputDevice {
            let warnings = layoutManager.validateLayout(against: outputDevice.maxOutputChannels)
            if !warnings.isEmpty {
                print("⚠️ Device compatibility warnings: \(warnings)")
            }
        }
    }

    private func startRecording() {
        if recordingVM.isRecording {
            recordingVM.stopRecording()
            return
        }
        
        guard let inputDevice = audioDeviceVM.selectedInputDevice,
              let outputDevice = audioDeviceVM.selectedOutputDevice else {
            print("❌ No audio devices selected")
            return
        }
        
        // For measurement recordings, use LayoutManager's layout
        if recordingType == .measurement {
            guard let layout = layoutManager.getCurrentLayout() else {
                print("❌ No valid layout selected for measurement recording")
                return
            }
            
            // Validate layout against device capabilities
            let layoutWarnings = layoutManager.validateLayout(against: outputDevice.maxOutputChannels)
            if !layoutWarnings.isEmpty {
                print("⚠️ Layout validation warnings: \(layoutWarnings)")
                // Could show alert dialog here for user confirmation
            }
            
            // Use the new RecordingViewModel integration methods
            recordingVM.startLayoutBasedRecording(
                layout: layout,
                measurementDir: workspaceManager.currentWorkspace.path,
                testSignal: testSignalPath,
                inputDevice: inputDevice,
                outputDevice: outputDevice,
                channelMapping: audioDeviceVM.channelMapping
            )
            
            // Set results URL for first expected file
            if let firstGroup = layout.groups.first {
                let fileName = "\(firstGroup.speakers.joined(separator: ",")).wav"
                recordingResultsURL = workspaceManager.currentWorkspace.appendingPathComponent(fileName)
            }
            
        } else {
            // Non-measurement recordings (room, headphone, test sweep)
            recordingVM.startStandardRecording(
                type: recordingType,
                measurementDir: workspaceManager.currentWorkspace.path,
                testSignal: testSignalPath,
                outputFile: finalOutputPath,
                inputDevice: inputDevice,
                outputDevice: outputDevice
            )
            
            recordingResultsURL = URL(fileURLWithPath: finalOutputPath)
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
    @Binding var recordingType: RecordingType
    @Binding var selectedLayoutName: String
    let isRecording: Bool
    let canStartRecording: Bool
    let finalOutputPath: String
    let currentWorkspace: String
    let startRecordingAction: () -> Void
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    
    @StateObject private var layoutManager = LayoutManager.shared
    
    private var currentLayout: SpeakerLayout? {
        layoutManager.getCurrentLayout()
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
                        ForEach(RecordingType.allCases, id: \.self) { type in 
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Show speaker layout picker only for measurement recordings
                    if recordingType == .measurement && !layoutManager.availableLayouts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "speaker.wave.3")
                                    .foregroundColor(.accentColor)
                                Text("Speaker Layout")
                                    .font(.headline)
                                Spacer()
                                
                                if let layout = currentLayout {
                                    HStack {
                                        Text("\(layout.totalSpeakers) channels")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                                
                                        // Show warning if layout exceeds device capabilities
                                        if let outputDevice = audioDeviceVM.selectedOutputDevice {
                                            let requiredChannels = layout.totalSpeakers
                                            if outputDevice.maxOutputChannels < requiredChannels {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.orange)
                                                    .font(.caption)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                                    
                            Picker("Speaker Layout", selection: $selectedLayoutName) {
                                ForEach(layoutManager.availableLayoutNames, id: \.self) { layoutName in
                                    if let layout = layoutManager.availableLayouts[layoutName] {
                                        Label(layout.displayName, systemImage: layout.icon)
                                            .tag(layoutName)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                                    
                            // Show layout validation warnings
                            if let outputDevice = audioDeviceVM.selectedOutputDevice,
                                let layout = currentLayout {
                                let requiredChannels = layout.totalSpeakers
                                if outputDevice.maxOutputChannels < requiredChannels {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            Text("Layout requires \(requiredChannels) channels but device only has \(outputDevice.maxOutputChannels)")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                                    
                            // Show expected recording files
                            if let layout = currentLayout, layout.groups.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Recording sequence:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), alignment: .leading, spacing: 4) {
                                        ForEach(Array(layout.groups.enumerated()), id: \.offset) { index, group in
                                            Text("\(group.speakers.joined(separator: ",")).wav")
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
                                    Text("\(group.speakers.joined(separator: ",")).wav")
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
    let recordingType: RecordingType
    let currentLayout: SpeakerLayout?
    @Binding var showingTestSignalPicker: Bool
    @ObservedObject var workspaceManager: WorkspaceManager
    
    var body: some View {
        GroupBox("Recording Configuration") {
            VStack(spacing: 16) {
                // Test Signal
                VStack(alignment: .leading, spacing: 8) {
                    Label("Test Signal", systemImage: "waveform")
                        .font(.headline)
                    
                    // Check if test signal is bundled and valid
                    let isBundledSignal = !testSignalPath.isEmpty &&
                        (testSignalPath.contains("/Scripts/data/") ||
                         testSignalPath.contains("Bundle.main"))
                    let isValidSignal = !testSignalPath.isEmpty &&
                        FileManager.default.fileExists(atPath: testSignalPath)
                    
                    if isBundledSignal && isValidSignal {
                        // For valid bundled signals, only show the Browse button
                        HStack {
                            Spacer()
                            Button("Browse") {
                                showingTestSignalPicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        // For custom or missing signals, show the full TextField interface
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
                                    Text("• \(group.speakers.joined(separator: ",") + ".wav")")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else if useCustomName {
                            TextField("Enter filename...", text: $outputFileName)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text("Will use: \(layout.groups.first?.speakers.joined(separator: ",") ?? "measurement").wav")
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
