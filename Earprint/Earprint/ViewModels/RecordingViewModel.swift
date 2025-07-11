#if canImport(SwiftUI)
import SwiftUI
import Foundation
import Combine

// MARK: - Recording State (single definition)
enum RecordingState: Equatable {
    case idle
    case scanning
    case validating
    case saving
    case recording(progress: Double?, remainingTime: Double?)
    case completed(outputFile: String)
    case error(String)
    
    var isProcessing: Bool {
        switch self {
        case .scanning, .validating, .saving, .recording:
            return true
        default:
            return false
        }
    }
    
    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning), (.validating, .validating), (.saving, .saving):
            return true
        case let (.recording(p1, t1), .recording(p2, t2)):
            return p1 == p2 && t1 == t2
        case let (.completed(f1), .completed(f2)):
            return f1 == f2
        case let (.error(e1), .error(e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

// MARK: - Recording State (multigroup)
enum SequentialRecordingState: Equatable {
    case idle
    case recordingGroup(currentGroup: Int, totalGroups: Int, groupName: String)
    case betweenGroups(nextGroup: Int, totalGroups: Int, nextGroupName: String)
    case completed(totalRecordings: Int)
    case error(String)
}

// MARK: - Enhanced RecordingViewModel (macOS)
@MainActor
final class RecordingViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var recordingState: RecordingState = .idle
    @Published var hasFiles: Bool = false
    @Published var recordings: [RecordingInfo] = []
    @Published var latestRecording: RecordingInfo?
    @Published var validationResults: [String: FileValidationResult] = [:]
    @Published var selectedRecordings: Set<String> = []
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var sequentialState: SequentialRecordingState = .idle
    @Published var currentRecordingConfiguration: RecordingConfiguration?
    @Published var remainingGroups: [RecordingGroup] = []
    
    // MARK: - Computed Properties
    var recordingName: String {
        latestRecording?.name ?? "No recordings"
    }
    
    var measurementHasFiles: Bool {
        hasFiles
    }
    
    var canSave: Bool {
        !selectedRecordings.isEmpty && !recordingState.isProcessing
    }

    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    var recordingProgress: Double? {
        if case .recording(let progress, _) = recordingState { return progress }
        return nil
    }

    var recordingRemainingTime: Double? {
        if case .recording(_, let time) = recordingState { return time }
        return nil
    }

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private var recordingProcess: Process?
    private var recordingTimer: Timer?
    
    // MARK: - Utility Properties
    private var scriptsRoot: URL {
        (Bundle.main.resourceURL ?? packageRoot).appendingPathComponent("Scripts")
    }

    private var embeddedPythonURL: URL? {
        Bundle.main.url(forResource: "Python", withExtension: "framework", subdirectory: "EmbeddedPython")?
            .appendingPathComponent("Versions")
            .appendingPathComponent("Current")
            .appendingPathComponent("bin/python3")
    }

    private func scriptPath(_ name: String) -> String {
        scriptsRoot.appendingPathComponent(name).path
    }

    private var packageRoot: URL {
        Bundle.main.bundleURL
    }

    // MARK: - Recording Operations
    func startRecording(with configuration: RecordingConfiguration) {
        guard !isRecording else { return }
            
        // Validate configuration first
        if let error = validateRecordingConfiguration(configuration) {
            recordingState = .error(error)
            return
        }
            
        recordingState = .recording(progress: nil, remainingTime: nil)
            
        // Choose the right Python tool based on recording complexity
        if let layout = configuration.speakerLayout, shouldUseCaptureWizard(layout) {
            // Complex layout recording -> use capture_wizard.py
            let args = buildCaptureWizardArgs(configuration)
            startPython(script: scriptPath("capture_wizard.py"), args: args)
        } else {
            // Simple recording -> use recorder.py
            let args = buildRecordingArgs(configuration)
            startPython(script: scriptPath("recorder.py"), args: args)
        }
    }
    
    private func shouldUseCaptureWizard(_ layoutName: String) -> Bool {
        // Use capture_wizard for multi-group layouts
        return !["2.0", "1.0", "headphone", "room"].contains(layoutName)
    }

    private func buildCaptureWizardArgs(_ configuration: RecordingConfiguration) -> [String] {
        let baseArgs = [
            "--layout", configuration.speakerLayout ?? "2.0",
            "--dir", configuration.measurementDir,
            "--input_device", configuration.recordingDevice,
            "--output_device", configuration.playbackDevice
        ]
        
        // Add custom test signals if specified and not default
        if !configuration.testSignal.contains("sweep-6.15s-48000Hz") {
            return baseArgs + ["--stereo_sweep", configuration.testSignal]
        }
        
        return baseArgs
    }

    func stopRecording() {
        cancelRecording()
    }

    private func buildRecordingArgs(_ configuration: RecordingConfiguration) -> [String] {
            // Determine if this is a room recording
            let isRoomRecording = configuration.outputFile?.lowercased().contains("room") ?? false
            
            // Determine proper channel count
            let channels: Int
            if isRoomRecording {
                channels = 1  // Room recordings must be mono
            } else {
                channels = configuration.outputChannels?.count ?? 2  // Default to stereo for measurements
            }
            
            // Build args with CORRECT CLI arguments that match the Python backend
            let args = [
                "--play", configuration.testSignal,
                "--record", configuration.outputFile ?? "\(configuration.measurementDir)/recording.wav",
                "--output_device", configuration.playbackDevice,
                "--input_device", configuration.recordingDevice,
                "--channels", String(channels),
                "--print_progress"
            ]
            
            return args
    }

    private func cancelRecording() {
        recordingProcess?.terminate()
        recordingProcess = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingState = .idle
    }

    // MARK: - Python Execution Infrastructure
    private func startPython(script: String, args: [String]) {
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        
        if let py = embeddedPythonURL {
            process.executableURL = py
            process.arguments = [script] + args
            process.environment = [
                "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                "PYTHONPATH": scriptsRoot.path
            ]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", script] + args
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.processRecordingOutput(output)
                }
            }
        }
        
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.recordingTerminated(with: process.terminationStatus)
            }
        }
        
        do {
            try process.run()
            self.recordingProcess = process
            startRecordingProgressMonitoring()
        } catch {
            recordingState = .error("Failed to start recording process: \(error.localizedDescription)")
            print("Failed to start recording process: \(error.localizedDescription)")
        }
    }

    private func processRecordingOutput(_ output: String) {
        print("Recording output: \(output)")
        parseRecordingProgressFromOutput(output)
    }

    private func parseRecordingProgressFromOutput(_ output: String) {
        // Parse progress from recorder.py (PROGRESS 0.750 15.2 format)
        if let progressMatch = output.range(of: #"PROGRESS (\d+\.?\d*) (\d+\.?\d*)"#, options: .regularExpression) {
            let progressStr = String(output[progressMatch])
            let components = progressStr.replacingOccurrences(of: "PROGRESS ", with: "").split(separator: " ")
            
            if components.count == 2,
                let progress = Double(components[0]),
                let remaining = Double(components[1]) {
                recordingState = .recording(progress: progress, remainingTime: remaining)
                return
            }
        }
            
        // Parse progress from recorder.py (percentage format)
        if let progressMatch = output.range(of: #"(\d+\.?\d*)%"#, options: .regularExpression) {
            let progressStr = String(output[progressMatch])
            if let progressValue = Double(progressStr.replacingOccurrences(of: "%", with: "")) {
                let normalizedProgress = progressValue / 100.0
                if case .recording(_, let time) = recordingState {
                    recordingState = .recording(progress: normalizedProgress, remainingTime: time)
                }
                return
            }
        }
            
        // Parse capture_wizard.py status messages
        if output.contains("Recording layout") {
            recordingState = .recording(progress: 0.0, remainingTime: nil)
        } else if output.contains("Insert binaural microphones") {
            recordingState = .recording(progress: 0.1, remainingTime: nil)
        } else if output.contains("Position for") {
            recordingState = .recording(progress: 0.3, remainingTime: nil)
        } else if output.contains("✅ Capture completed") {
            recordingState = .completed(outputFile: "Capture completed")
        } else if output.contains("⚠️  Recording failed") {
            recordingState = .error("Recording failed")
        }
    }

    // MARK: - Updated Recording Termination Handler

    private func recordingTerminated(with status: Int32) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingProcess = nil
        
        if status == 0 {
            // Check if this is part of a sequential recording
            if case .recordingGroup = sequentialState {
                onGroupRecordingCompleted()
            } else {
                recordingState = .completed(outputFile: "Recording completed")
            }
            print("Recording completed successfully")
        } else {
            if case .recordingGroup = sequentialState {
                sequentialState = .error("Group recording failed with status: \(status)")
            }
            recordingState = .error("Recording failed with status: \(status)")
            print("Recording failed with status: \(status)")
        }
    }

    private func startRecordingProgressMonitoring() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Update recording UI or check process status
        }
    }

    // MARK: - Specialized Recording Methods
    func recordHeadphoneEQ(configuration: RecordingConfiguration) {
        let file = URL(fileURLWithPath: configuration.measurementDir)
            .appendingPathComponent("headphones.wav").path
            
        let updatedConfig = RecordingConfiguration(
            measurementDir: configuration.measurementDir,
            testSignal: configuration.testSignal,
            playbackDevice: configuration.playbackDevice,
            recordingDevice: configuration.recordingDevice,
            outputFile: file,
            speakerLayout: nil,
            recordingGroup: nil,
            outputChannels: [0, 1],  // Headphones are always stereo
            inputChannels: [0, 1]    // Binaural mics are always stereo
        )
            
            startRecording(with: updatedConfig)
    }

    func recordRoomResponse(configuration: RecordingConfiguration) {
        let file = URL(fileURLWithPath: configuration.measurementDir)
            .appendingPathComponent("room.wav").path
            
        let updatedConfig = RecordingConfiguration(
            measurementDir: configuration.measurementDir,
            testSignal: configuration.testSignal,
            playbackDevice: configuration.playbackDevice,
            recordingDevice: configuration.recordingDevice,
            outputFile: file,
            speakerLayout: nil,  // Not needed for room recording
            recordingGroup: nil, // Not needed for room recording
            outputChannels: nil, // Room recordings don't use output channels array
            inputChannels: [0]   // Room recordings use single input channel (mono)
        )
            
        startRecording(with: updatedConfig)
    }

    // MARK: - Sequential Recording Methods

    func startSequentialRecording(with configuration: RecordingConfiguration, layout: SpeakerLayoutInfo) {
        guard !layout.groups.isEmpty else {
            recordingState = .error("Invalid speaker layout: no groups defined")
            return
        }
        
        // Store configuration and setup sequence
        currentRecordingConfiguration = configuration
        remainingGroups = layout.groups
        sequentialState = .idle
        
        // Start with first group
        startNextGroupRecording()
    }

    private func startNextGroupRecording() {
        guard let baseConfig = currentRecordingConfiguration,
              !remainingGroups.isEmpty else {
            completeSequentialRecording()
            return
        }
        
        let currentGroup = remainingGroups.removeFirst()
        let groupIndex = (currentRecordingConfiguration?.speakerLayout == nil ? 0 :
                         (getSpeakerLayoutInfo()?.groups.count ?? 1) - remainingGroups.count - 1)
        let totalGroups = getSpeakerLayoutInfo()?.groups.count ?? 1
        
        // Update state
        sequentialState = .recordingGroup(
            currentGroup: groupIndex + 1,
            totalGroups: totalGroups,
            groupName: currentGroup.name
        )
        
        // Create configuration for this specific group
        let groupOutputPath = baseConfig.measurementDir.appending("/\(currentGroup.filename)")
        
        let groupConfig = RecordingConfiguration(
            measurementDir: baseConfig.measurementDir,
            testSignal: baseConfig.testSignal,
            playbackDevice: baseConfig.playbackDevice,
            recordingDevice: baseConfig.recordingDevice,
            outputFile: groupOutputPath,
            speakerLayout: baseConfig.speakerLayout,
            recordingGroup: currentGroup.name,
            outputChannels: getOutputChannelsForGroup(currentGroup),
            inputChannels: baseConfig.inputChannels
        )
        
        // Start recording this group
        startRecording(with: groupConfig)
    }

    private func getOutputChannelsForGroup(_ group: RecordingGroup) -> [Int]? {
        // Map speaker names to output channels
        // This would need to be implemented based on your channel mapping logic
        // For now, return default stereo mapping
        return [0, 1]
    }

    private func getSpeakerLayoutInfo() -> SpeakerLayoutInfo? {
        // Get current layout info - this would need to be passed in or stored
        return nil // Placeholder
    }

    func onGroupRecordingCompleted() {
        if remainingGroups.isEmpty {
            completeSequentialRecording()
        } else {
            // Show transition UI for next group
            let nextGroup = remainingGroups.first!
            let nextGroupIndex = (getSpeakerLayoutInfo()?.groups.count ?? 1) - remainingGroups.count + 1
            let totalGroups = getSpeakerLayoutInfo()?.groups.count ?? 1
            
            sequentialState = .betweenGroups(
                nextGroup: nextGroupIndex,
                totalGroups: totalGroups,
                nextGroupName: nextGroup.name
            )
            
            // Auto-advance after delay, or wait for user input
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.startNextGroupRecording()
            }
        }
    }

    private func completeSequentialRecording() {
        let totalRecordings = getSpeakerLayoutInfo()?.groups.count ?? 1
        sequentialState = .completed(totalRecordings: totalRecordings)
        recordingState = .completed(outputFile: "Sequential recording completed")
        
        // Clean up
        currentRecordingConfiguration = nil
        remainingGroups = []
        
        // Auto-reset after showing completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.sequentialState = .idle
        }
    }

    func cancelSequentialRecording() {
        cancelRecording() // Stop current recording
        currentRecordingConfiguration = nil
        remainingGroups = []
        sequentialState = .idle
    }

    // MARK: - Smart Test Signal Selection (Add to RecordingViewModel)

    /// Get the appropriate test signal file for a specific recording group
    private func getTestSignalForGroup(_ group: RecordingGroup) -> String {
        guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
            print("❌ Scripts directory not found")
            return getDefaultTestSignal()
        }
        
        let dataDir = scriptsRoot.appendingPathComponent("data")
        
        if group.speakers.count == 1 {
            // Single speaker - prefer mono sweep, fallback to stereo
            let speaker = group.speakers[0]
            
            // Try mono sweep first
            let monoFile = dataDir.appendingPathComponent("sweep-seg-\(speaker)-mono-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav")
            if fileManager.fileExists(atPath: monoFile.path) {
                print("✅ Using mono sweep for single speaker \(speaker): \(monoFile.lastPathComponent)")
                return monoFile.path
            }
            
            // Fallback to stereo sweep for single speaker
            let stereoFile = dataDir.appendingPathComponent("sweep-seg-\(speaker)-stereo-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav")
            if fileManager.fileExists(atPath: stereoFile.path) {
                print("✅ Using stereo sweep for single speaker \(speaker): \(stereoFile.lastPathComponent)")
                return stereoFile.path
            }
            
            print("⚠️ No specific sweep found for speaker \(speaker), using default")
            
        } else if group.speakers.count == 2 {
            // Stereo pair - use stereo sweep
            let groupName = group.speakers.joined(separator: ",")
            let stereoFile = dataDir.appendingPathComponent("sweep-seg-\(groupName)-stereo-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav")
            
            if fileManager.fileExists(atPath: stereoFile.path) {
                print("✅ Using stereo sweep for pair \(groupName): \(stereoFile.lastPathComponent)")
                return stereoFile.path
            }
            
            print("⚠️ No specific sweep found for pair \(groupName), using default")
            
        } else {
            // Multi-speaker group (more than 2) - this might need special handling
            let groupName = group.speakers.joined(separator: ",")
            let multiFile = dataDir.appendingPathComponent("sweep-seg-\(groupName)-stereo-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav")
            
            if fileManager.fileExists(atPath: multiFile.path) {
                print("✅ Using multi-speaker sweep for \(groupName): \(multiFile.lastPathComponent)")
                return multiFile.path
            }
            
            print("⚠️ No specific sweep found for multi-speaker group \(groupName), using default")
        }
        
        // Final fallback to default sweep
        return getDefaultTestSignal()
    }

    /// Get the default test signal path
    private func getDefaultTestSignal() -> String {
        guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
            print("❌ Scripts directory not found")
            return ""
        }
        
        let dataDir = scriptsRoot.appendingPathComponent("data")
        let defaultSweep = dataDir.appendingPathComponent("sweep-6.15s-48000Hz-32bit-2.93Hz-24000Hz.wav")
        
        if fileManager.fileExists(atPath: defaultSweep.path) {
            print("✅ Using default sweep: \(defaultSweep.lastPathComponent)")
            return defaultSweep.path
        }
        
        print("❌ No default sweep file found")
        return ""
    }

    /// Map speaker groups to appropriate output channels
    private func getOutputChannelsForGroup(_ group: RecordingGroup) -> [Int] {
        if group.speakers.count == 1 {
            // Single speaker - map to appropriate channel
            let speaker = group.speakers[0]
            switch speaker {
            case "FL": return [0]      // Left channel
            case "FR": return [1]      // Right channel
            case "FC": return [0, 1]   // Center - send to both channels
            case "SL": return [0]      // Side left
            case "SR": return [1]      // Side right
            case "BL": return [0]      // Back left
            case "BR": return [1]      // Back right
            case "TFL": return [0]     // Top front left
            case "TFR": return [1]     // Top front right
            case "TBL": return [0]     // Top back left
            case "TBR": return [1]     // Top back right
            default: return [0, 1]     // Default to stereo
            }
        } else if group.speakers.count == 2 {
            // Stereo pair - use both channels
            return [0, 1]
        } else {
            // Multi-speaker group - use stereo for now
            // This might need more sophisticated mapping for complex layouts
            return [0, 1]
        }
    }

    /// Validate that appropriate test signals exist for a speaker layout
    func validateTestSignalsForLayout(_ layoutInfo: SpeakerLayoutInfo) -> [String] {
        var missingSignals: [String] = []
        
        for group in layoutInfo.groups {
            let testSignal = getTestSignalForGroup(group)
            if testSignal.isEmpty || !fileManager.fileExists(atPath: testSignal) {
                missingSignals.append(group.name)
            }
        }
        
        return missingSignals
    }

    /// Enhanced recording method with smart test signal selection
    func startRecordingWithLayout(
        configuration: RecordingConfiguration,
        layout: SpeakerLayoutInfo,
        group: RecordingGroup? = nil
    ) {
        guard !isRecording else { return }
        
        // Validate that we have required test signals
        let missingSignals = validateTestSignalsForLayout(layout)
        if !missingSignals.isEmpty {
            recordingState = .error("Missing test signals for groups: \(missingSignals.joined(separator: ", "))")
            return
        }
            
        // Determine which group to record (first group if not specified)
        let targetGroup = group ?? layout.groups.first
        guard let recordingGroup = targetGroup else {
            recordingState = .error("No recording groups found in layout")
            return
        }
            
        // Get appropriate test signal for this group
        let selectedTestSignal = getTestSignalForGroup(recordingGroup)
        guard !selectedTestSignal.isEmpty else {
            recordingState = .error("No suitable test signal found for group: \(recordingGroup.name)")
            return
        }
            
        // Create output file path
        let outputFile = URL(fileURLWithPath: configuration.measurementDir)
            .appendingPathComponent(recordingGroup.filename).path
        
        // Build configuration with smart selections
        let enhancedConfig = RecordingConfiguration(
            measurementDir: configuration.measurementDir,
            testSignal: selectedTestSignal,
            playbackDevice: configuration.playbackDevice,
            recordingDevice: configuration.recordingDevice,
            outputFile: outputFile,
            speakerLayout: layout.name,
            recordingGroup: recordingGroup.name,
            outputChannels: getOutputChannelsForGroup(recordingGroup),
            inputChannels: configuration.inputChannels
        )
            
        // Start the recording
        startRecording(with: enhancedConfig)
    }

    /// Validate configuration before recording
    private func validateRecordingConfiguration(_ configuration: RecordingConfiguration) -> String? {
        // Check test signal exists
        if !fileManager.fileExists(atPath: configuration.testSignal) {
            return "Test signal file not found: \(configuration.testSignal)"
        }
            
        // Check measurement directory exists or can be created
        let measurementDir = URL(fileURLWithPath: configuration.measurementDir)
        if !fileManager.fileExists(atPath: measurementDir.path) {
            do {
                try fileManager.createDirectory(at: measurementDir, withIntermediateDirectories: true)
            } catch {
                return "Cannot create measurement directory: \(error.localizedDescription)"
            }
        }
            
        // Check devices are specified
        if configuration.playbackDevice.isEmpty {
            return "No playback device specified"
        }
        
        if configuration.recordingDevice.isEmpty {
            return "No recording device specified"
        }
            
        return nil // All good
    }

    /// Get available test signals for diagnostics
    func getAvailableTestSignals() -> [String] {
        guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
            return []
        }
        
        let dataDir = scriptsRoot.appendingPathComponent("data")
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)
            return contents
                .filter { $0.pathExtension.lowercased() == "wav" && $0.lastPathComponent.contains("sweep") }
                .map { $0.lastPathComponent }
                .sorted()
        } catch {
            print("Failed to list test signals: \(error)")
            return []
        }
    }

    // MARK: - File Management Methods
    func validatePaths(_ measurementDir: String) {
        guard !measurementDir.isEmpty else {
            recordingState = .idle
            hasFiles = false
            recordings = []
            latestRecording = nil
            return
        }
        
        recordingState = .scanning
        
        Task {
            await scanDirectory(measurementDir)
        }
    }
    
    func refreshRecordings(_ measurementDir: String) {
        validatePaths(measurementDir)
    }
    
    func saveFiles(
        files: [URL],
        measurementDir: String,
        destination: String,
        completion: @escaping (String) -> Void
    ) {
        guard !recordingState.isProcessing else {
            completion("Save operation already in progress")
            return
        }
        
        recordingState = .saving
        
        Task {
            await performSaveOperation(
                files: files,
                destination: destination,
                completion: completion
            )
        }
    }
    
    func saveLatest(
        from measurementDir: String,
        to destination: String,
        completion: @escaping (String) -> Void
    ) {
        guard let latest = latestRecording else {
            completion("No latest recording found")
            return
        }
        
        let sourceURL = URL(fileURLWithPath: latest.path)
        saveFiles(
            files: [sourceURL],
            measurementDir: measurementDir,
            destination: destination,
            completion: completion
        )
    }
    
    func saveSelected(
        from measurementDir: String,
        to destination: String,
        completion: @escaping (String) -> Void
    ) {
        let selectedFiles = recordings
            .filter { selectedRecordings.contains($0.name) }
            .map { URL(fileURLWithPath: $0.path) }
        
        guard !selectedFiles.isEmpty else {
            completion("No files selected")
            return
        }
        
        saveFiles(
            files: selectedFiles,
            measurementDir: measurementDir,
            destination: destination,
            completion: completion
        )
    }
    
    func deleteRecording(name: String, completion: @escaping (String) -> Void) {
        guard let recording = recordings.first(where: { $0.name == name }) else {
            completion("Recording not found: \(name)")
            return
        }
        
        let url = URL(fileURLWithPath: recording.path)
        
        do {
            try fileManager.removeItem(at: url)
            recordings.removeAll { $0.name == name }
            selectedRecordings.remove(name)
            
            if latestRecording?.name == name {
                latestRecording = recordings.max { $0.dateModified < $1.dateModified }
            }
            
            hasFiles = !recordings.isEmpty
            completion("Deleted \(name)")
        } catch {
            completion("Failed to delete \(name): \(error.localizedDescription)")
        }
    }
    
    func toggleSelection(for recordingName: String) {
        if selectedRecordings.contains(recordingName) {
            selectedRecordings.remove(recordingName)
        } else {
            selectedRecordings.insert(recordingName)
        }
    }
    
    func selectAll() {
        selectedRecordings = Set(recordings.map { $0.name })
    }
    
    func deselectAll() {
        selectedRecordings.removeAll()
    }
    
    // MARK: - Speaker Layout Methods
    func getSpeakerLayouts(completion: @escaping ([String: SpeakerLayoutInfo]) -> Void) {
        print("🔍 Loading speaker layouts from Python...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
                print("❌ Scripts directory not found for speaker layouts")
                // Fallback to basic layouts
                DispatchQueue.main.async {
                    let fallbackLayouts = RecordingViewModel.createFallbackLayouts()
                    completion(fallbackLayouts)
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
                    """
                    import json, constants, sys
                    
                    def format_display_name(name):
                        if name == '2.0':
                            return 'Stereo (2.0)'
                        elif name == '5.1':
                            return '5.1 Surround'
                        elif name == '7.1':
                            return '7.1 Surround'
                        elif name.endswith('.4'):
                            return f'{name} Atmos'
                        elif name.endswith('.6'):
                            return f'{name} Atmos'
                        elif name.endswith('.2'):
                            return f'{name} Atmos'
                        elif name == 'ambisonics':
                            return 'Ambisonics'
                        elif name == '1.0':
                            return 'Mono (1.0)'
                        else:
                            return name
                    
                    def get_icon_for_layout(name):
                        if 'ambisonics' in name:
                            return 'globe'
                        elif '.4' in name or '.6' in name or '.2' in name:
                            return 'speaker.wave.1.arrowtriangles.up.right.down.left'
                        elif name == '1.0':
                            return 'speaker'
                        elif name == '2.0':
                            return 'speaker.2'
                        else:
                            return 'hifispeaker.2'
                    
                    layouts = {}
                    for name, groups in constants.SPEAKER_LAYOUTS.items():
                        layouts[name] = {
                            'name': name,
                            'displayName': format_display_name(name),
                            'groups': [{'name': ','.join(group), 'speakers': group} for group in groups],
                            'icon': get_icon_for_layout(name)
                        }
                    
                    print(f"Found {len(layouts)} layouts: {list(layouts.keys())}", file=sys.stderr)
                    json.dump(layouts, sys.stdout)
                    """
                ]
                process.environment = [
                    "PYTHONHOME": embeddedPythonURL.deletingLastPathComponent().deletingLastPathComponent().path,
                    "PYTHONPATH": scriptsRoot.path
                ]
                print("🔍 Using embedded Python for speaker layouts")
            } else {
                // Fallback to system Python with simpler approach
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "python3",
                    "-c",
                    """
                    import json, constants, sys
                    
                    print(f"Available layouts: {list(constants.SPEAKER_LAYOUTS.keys())}", file=sys.stderr)
                    
                    def format_display_name(name):
                        if name == '2.0':
                            return 'Stereo (2.0)'
                        elif name == '5.1':
                            return '5.1 Surround'
                        elif name == '7.1':
                            return '7.1 Surround'
                        elif name.endswith('.4'):
                            return f'{name} Atmos'
                        elif name.endswith('.6'):
                            return f'{name} Atmos'
                        elif name.endswith('.2'):
                            return f'{name} Atmos'
                        elif name == 'ambisonics':
                            return 'Ambisonics'
                        elif name == '1.0':
                            return 'Mono (1.0)'
                        else:
                            return name
                    
                    def get_icon_for_layout(name):
                        if 'ambisonics' in name:
                            return 'globe'
                        elif '.4' in name or '.6' in name or '.2' in name:
                            return 'airpodspro'
                        elif name == '1.0':
                            return 'speaker'
                        elif name == '2.0':
                            return 'speaker.2'
                        else:
                            return 'speaker.wave.3'
                    
                    layouts = {}
                    for name, groups in constants.SPEAKER_LAYOUTS.items():
                        layouts[name] = {
                            'name': name,
                            'displayName': format_display_name(name),
                            'groups': [{'name': ','.join(group), 'speakers': group} for group in groups],
                            'icon': get_icon_for_layout(name)
                        }
                    
                    print(f"Processed {len(layouts)} layouts", file=sys.stderr)
                    json.dump(layouts, sys.stdout)
                    """
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
                
                // Debug: Print raw data
                if let dataString = String(data: data, encoding: .utf8) {
                    print("📋 Raw Python output: \(dataString.prefix(500))...")
                }
                
                if let layoutsDict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                    let convertedLayouts = RecordingViewModel.convertPythonLayoutsToSwift(layoutsDict)
                    DispatchQueue.main.async {
                        print("✅ Loaded \(convertedLayouts.count) speaker layouts from Python")
                        completion(convertedLayouts)
                    }
                } else {
                    print("❌ Failed to parse speaker layouts from Python")
                    if let dataString = String(data: data, encoding: .utf8) {
                        print("Python output: \(dataString)")
                    }
                    // Fallback to basic layouts
                    DispatchQueue.main.async {
                        let fallbackLayouts = RecordingViewModel.createFallbackLayouts()
                        completion(fallbackLayouts)
                    }
                }
                
            } catch {
                print("❌ Failed to execute Python process for layouts: \(error)")
                // Fallback to basic layouts
                DispatchQueue.main.async {
                    let fallbackLayouts = RecordingViewModel.createFallbackLayouts()
                    completion(fallbackLayouts)
                }
            }
        }
    }
    
    private nonisolated static func convertPythonLayoutsToSwift(_ pythonLayouts: [String: [String: Any]]) -> [String: SpeakerLayoutInfo] {
        var swiftLayouts: [String: SpeakerLayoutInfo] = [:]
        
        for (key, layoutData) in pythonLayouts {
            guard let name = layoutData["name"] as? String,
                  let displayName = layoutData["displayName"] as? String,
                  let icon = layoutData["icon"] as? String,
                  let groupsData = layoutData["groups"] as? [[String: Any]] else {
                continue
            }
            
            let groups = groupsData.compactMap { groupData -> RecordingGroup? in
                guard let groupName = groupData["name"] as? String,
                      let speakers = groupData["speakers"] as? [String] else {
                    return nil
                }
                return RecordingGroup(name: groupName, speakers: speakers)
            }
            
            let layoutInfo = SpeakerLayoutInfo(
                name: name,
                displayName: displayName,
                groups: groups,
                icon: icon
            )
            
            swiftLayouts[key] = layoutInfo
        }
        
        return swiftLayouts
    }
    
    private nonisolated static func createFallbackLayouts() -> [String: SpeakerLayoutInfo] {
        print("✅ Using fallback speaker layouts")
        return [
            "2.0": SpeakerLayoutInfo(
                name: "2.0",
                displayName: "Stereo (2.0)",
                groups: [RecordingGroup(name: "FL,FR", speakers: ["FL", "FR"])],
                icon: "speaker.2"
            ),
            "5.1": SpeakerLayoutInfo(
                name: "5.1",
                displayName: "5.1 Surround",
                groups: [
                    RecordingGroup(name: "FL,FR", speakers: ["FL", "FR"]),
                    RecordingGroup(name: "FC", speakers: ["FC"]),
                    RecordingGroup(name: "BL,BR", speakers: ["BL", "BR"])
                ],
                icon: "speaker.wave.3"
            ),
            "7.1": SpeakerLayoutInfo(
                name: "7.1",
                displayName: "7.1 Surround",
                groups: [
                    RecordingGroup(name: "FL,FR", speakers: ["FL", "FR"]),
                    RecordingGroup(name: "FC", speakers: ["FC"]),
                    RecordingGroup(name: "SL,SR", speakers: ["SL", "SR"]),
                    RecordingGroup(name: "BL,BR", speakers: ["BL", "BR"])
                ],
                icon: "speaker.wave.3"
            ),
            "7.1.4": SpeakerLayoutInfo(
                name: "7.1.4",
                displayName: "7.1.4 Atmos",
                groups: [
                    RecordingGroup(name: "FL,FC,FR,SL,SR,BL,BR,TFL,TFR,TBL,TBR", speakers: ["FL", "FC", "FR", "SL", "SR", "BL", "BR", "TFL", "TFR", "TBL", "TBR"])
                ],
                icon: "airpodspro"
            )
        ]
    }
    
    // MARK: - Legacy Support Methods
    func updateLatestRecording(_ measurementDir: String) {
        validatePaths(measurementDir)
    }
    
    // MARK: - File Utility Methods
    func getRecordingSize(_ recording: RecordingInfo) -> String {
        ByteCountFormatter.string(fromByteCount: recording.size, countStyle: .file)
    }
    
    func getRecordingAge(_ recording: RecordingInfo) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: recording.dateModified, relativeTo: Date())
    }
    
    func isAudioFile(_ recording: RecordingInfo) -> Bool {
        let audioExtensions = ["wav", "aif", "aiff", "mp3", "flac", "m4a"]
        let ext = URL(fileURLWithPath: recording.path).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }
    
    func getMeasurementType(_ recording: RecordingInfo) -> String {
        let name = recording.name.lowercased()
        
        if name.contains("headphone") {
            return "Headphone EQ"
        } else if name.contains("room") {
            return "Room Response"
        } else if name.contains("sweep") {
            return "Test Sweep"
        } else if isAudioFile(recording) {
            return "Audio Recording"
        } else if name.hasSuffix(".csv") {
            return "Measurement Data"
        } else if name.hasSuffix(".json") {
            return "Configuration"
        } else {
            return "Unknown"
        }
    }
    
    func getValidationStatus(_ recording: RecordingInfo) -> String {
        guard let result = validationResults[recording.name] else {
            return "Not validated"
        }
        
        if result.isValid {
            return result.suggestions.isEmpty ? "Valid" : result.suggestions.first ?? "Valid"
        } else {
            return result.errorMessage ?? "Invalid"
        }
    }
    
    func getRecordingIcon(_ recording: RecordingInfo) -> String {
        if recording.isDirectory {
            return "folder"
        } else if isAudioFile(recording) {
            return "waveform"
        } else {
            let name = recording.name.lowercased()
            if name.hasSuffix(".csv") {
                return "tablecells"
            } else if name.hasSuffix(".json") {
                return "doc.text"
            } else if name.hasSuffix(".log") || name.hasSuffix(".txt") {
                return "doc.plaintext"
            } else {
                return "doc"
            }
        }
    }
    
    // MARK: - Private Methods
    private func scanDirectory(_ measurementDir: String) async {
        let dirURL = URL(fileURLWithPath: measurementDir)
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isDirectoryKey
                ],
                options: [.skipsHiddenFiles]
            )
            
            var recordingInfos: [RecordingInfo] = []
            
            for url in contents {
                // Skip the plots directory and its contents
                if url.lastPathComponent == "plots" {
                    continue
                }
                
                do {
                    let resourceValues = try url.resourceValues(forKeys: [
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isDirectoryKey
                    ])
                    
                    let info = RecordingInfo(
                        name: url.lastPathComponent,
                        path: url.path,
                        dateModified: resourceValues.contentModificationDate ?? Date.distantPast,
                        size: Int64(resourceValues.fileSize ?? 0),
                        isDirectory: resourceValues.isDirectory ?? false
                    )
                    recordingInfos.append(info)
                } catch {
                    // Skip files that can't be read
                    continue
                }
            }
            
            await MainActor.run {
                self.recordings = recordingInfos.sorted { $0.dateModified > $1.dateModified }
                self.latestRecording = recordingInfos.max { $0.dateModified < $1.dateModified }
                self.hasFiles = !recordingInfos.isEmpty
                self.recordingState = .idle
            }
            
            // Start validation in background
            await validateRecordings()
            
        } catch {
            await MainActor.run {
                self.recordings = []
                self.latestRecording = nil
                self.hasFiles = false
                self.recordingState = .error("Failed to scan directory: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.showErrorAlert = true
            }
        }
    }
    
    private func validateRecordings() async {
        await MainActor.run {
            self.recordingState = .validating
        }
        
        for recording in recordings {
            let result = performFileValidation(at: recording.path)
            await MainActor.run {
                self.validationResults[recording.name] = result
            }
        }
        
        await MainActor.run {
            self.recordingState = .idle
        }
    }
    
    private func performFileValidation(at path: String) -> FileValidationResult {
        let url = URL(fileURLWithPath: path)
        var suggestions: [String] = []
        
        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            return FileValidationResult(
                isValid: false,
                errorMessage: "File does not exist",
                suggestions: ["Check file path", "Refresh directory"]
            )
        }
        
        // Check if it's a wave file
        if url.pathExtension.lowercased() == "wav" {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: path)
                if let fileSize = attributes[.size] as? Int64, fileSize == 0 {
                    suggestions.append("File is empty")
                    return FileValidationResult(
                        isValid: false,
                        errorMessage: "Empty audio file",
                        suggestions: suggestions
                    )
                }
            } catch {
                return FileValidationResult(
                    isValid: false,
                    errorMessage: "Cannot read file attributes",
                    suggestions: ["Check file permissions"]
                )
            }
            
            return FileValidationResult(isValid: true, errorMessage: nil, suggestions: [])
        }
        
        // Check for common measurement files
        let commonExtensions = ["csv", "json", "txt", "log"]
        if commonExtensions.contains(url.pathExtension.lowercased()) {
            suggestions.append("Measurement data file")
            return FileValidationResult(isValid: true, errorMessage: nil, suggestions: suggestions)
        }
        
        // Unknown file type
        suggestions.append("Unknown file type")
        return FileValidationResult(
            isValid: true,
            errorMessage: nil,
            suggestions: suggestions
        )
    }
    
    private func performSaveOperation(
        files: [URL],
        destination: String,
        completion: @escaping (String) -> Void
    ) async {
        let destinationURL = URL(fileURLWithPath: destination)
        
        do {
            // Create destination directory if needed
            try fileManager.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            var savedCount = 0
            var errors: [String] = []
            
            for fileURL in files {
                let destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
                
                do {
                    // Remove existing file if it exists
                    if fileManager.fileExists(atPath: destURL.path) {
                        try fileManager.removeItem(at: destURL)
                    }
                    
                    try fileManager.copyItem(at: fileURL, to: destURL)
                    savedCount += 1
                } catch {
                    errors.append("Failed to copy \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                self.recordingState = .idle
                
                if errors.isEmpty {
                    completion("Successfully saved \(savedCount) file(s) to \(destination)")
                } else {
                    let errorMessage = "Saved \(savedCount) files with \(errors.count) errors:\n" + errors.joined(separator: "\n")
                    completion(errorMessage)
                }
            }
            
        } catch {
            await MainActor.run {
                self.recordingState = .error("Save operation failed")
                self.errorMessage = error.localizedDescription
                self.showErrorAlert = true
                completion("Failed to create destination directory: \(error.localizedDescription)")
            }
        }
    }
}

#else

// MARK: - Non-macOS stub implementation
final class RecordingViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var hasFiles: Bool = false
    @Published var recordings: [RecordingInfo] = []
    @Published var latestRecording: RecordingInfo?
    @Published var validationResults: [String: FileValidationResult] = [:]
    @Published var selectedRecordings: Set<String> = []
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    
    var recordingName: String { "No recordings" }
    var measurementHasFiles: Bool { false }
    var canSave: Bool { false }
    var isRecording: Bool { false }
    var recordingProgress: Double? { nil }
    var recordingRemainingTime: Double? { nil }
    
    func startRecording(with configuration: RecordingConfiguration) {}
    func stopRecording() {}
    func recordHeadphoneEQ(configuration: RecordingConfiguration) {}
    func recordRoomResponse(configuration: RecordingConfiguration) {}
    func validatePaths(_ measurementDir: String) {}
    func refreshRecordings(_ measurementDir: String) {}
    func saveFiles(files: [URL], measurementDir: String, destination: String, completion: @escaping (String) -> Void) {}
    func saveLatest(from measurementDir: String, to destination: String, completion: @escaping (String) -> Void) {}
    func saveSelected(from measurementDir: String, to destination: String, completion: @escaping (String) -> Void) {}
    func deleteRecording(name: String, completion: @escaping (String) -> Void) {}
    func toggleSelection(for recordingName: String) {}
    func selectAll() {}
    func deselectAll() {}
    func updateLatestRecording(_ measurementDir: String) {}
    func getSpeakerLayouts(completion: @escaping ([String: SpeakerLayoutInfo]) -> Void) {}
    func getRecordingSize(_ recording: RecordingInfo) -> String { "" }
    func getRecordingAge(_ recording: RecordingInfo) -> String { "" }
    func isAudioFile(_ recording: RecordingInfo) -> Bool { false }
    func getMeasurementType(_ recording: RecordingInfo) -> String { "" }
    func getValidationStatus(_ recording: RecordingInfo) -> String { "" }
    func getRecordingIcon(_ recording: RecordingInfo) -> String { "" }
}

#endif
