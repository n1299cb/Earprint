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

enum SequentialRecordingState: Equatable {
    case idle
    case preparing(totalGroups: Int)
    case recordingGroup(currentGroup: Int, totalGroups: Int, groupName: String)
    case betweenGroups(nextGroup: Int, totalGroups: Int, nextGroupName: String)
    case completed
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .idle, .completed, .error:
            return false
        case .preparing, .recordingGroup, .betweenGroups:
            return true
        }
    }
    
    var progressDescription: String {
        switch self {
        case .idle:
            return ""
        case .preparing(let total):
            return "Preparing to record \(total) groups..."
        case .recordingGroup(let current, let total, let name):
            return "Recording group \(current)/\(total): \(name)"
        case .betweenGroups(let next, let total, let name):
            return "Preparing next group \(next)/\(total): \(name)"
        case .completed:
            return "Sequential recording completed"
        case .error(let message):
            return "Error: \(message)"
        }
    }
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
    @Published var remainingGroups: [SpeakerGroup] = []
    
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
                channels = 2  // Default to stereo for measurements
            }
            
            // DEBUG:
            print("Swift passing devices - Input: '\(configuration.recordingDevice)', Output: '\(configuration.playbackDevice)'")
        
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

    func startSequentialRecording(with configuration: RecordingConfiguration, layout: SpeakerLayout) {
        guard !layout.groups.isEmpty else {
            recordingState = .error("Invalid speaker layout: no groups defined")
            return
        }
        
        // Store configuration and setup sequence
        currentRecordingConfiguration = configuration
        remainingGroups = layout.groups
        sequentialState = .preparing(totalGroups: layout.groups.count)
            
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
        let groupIndex = getTotalGroupCount() - remainingGroups.count
        let totalGroups = getTotalGroupCount()
        
        sequentialState = .recordingGroup(
            currentGroup: groupIndex,
            totalGroups: totalGroups,
            groupName: currentGroup.name
        )
        
        // Use basic channel mapping - device compatibility handled at RecordingView level
        let outputChannels = getOutputChannelsForGroup(currentGroup)
        
        let fileName = "\(currentGroup.speakers.joined(separator: ",")).wav"
        let groupOutputPath = "\(baseConfig.measurementDir)/\(fileName)"
        
        let groupConfig = RecordingConfiguration(
            measurementDir: baseConfig.measurementDir,
            testSignal: baseConfig.testSignal,
            playbackDevice: baseConfig.playbackDevice,
            recordingDevice: baseConfig.recordingDevice,
            outputFile: groupOutputPath,
            speakerLayout: baseConfig.speakerLayout,
            recordingGroup: currentGroup.name,
            outputChannels: outputChannels,
            inputChannels: baseConfig.inputChannels
        )
        
        startRecording(with: groupConfig)
    }

    private func getOutputChannelsForGroup(
        _ group: SpeakerGroup,
        channelMapping: ChannelMapping? = nil
    ) -> [Int] {
        // Priority 1: Use explicit user channel mapping if available
        if let mapping = channelMapping,
           mapping.outputChannels.count >= group.speakers.count {
            return Array(mapping.outputChannels.prefix(group.speakers.count))
        }
        
        // Priority 2: Use intelligent speaker-based mapping
        return mapSpeakersToChannels(group.speakers)
    }

    func onGroupRecordingCompleted() {
        if remainingGroups.isEmpty {
            completeSequentialRecording()
        } else {
            // Show transition UI for next group
            let nextGroup = remainingGroups.first!
            let nextGroupIndex = getTotalGroupCount() - remainingGroups.count + 1
            let totalGroups = getTotalGroupCount()
            
            sequentialState = .betweenGroups(
                nextGroup: nextGroupIndex,
                totalGroups: totalGroups,
                nextGroupName: nextGroup.name
            )
            
            // Auto-advance after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.startNextGroupRecording()
            }
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
    private func getTestSignalForGroup(_ group: SpeakerGroup) -> String {
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
    private func mapSpeakersToChannels(_ speakers: [String]) -> [Int] {
        if speakers.count == 1 {
            // Single speaker - map to correct channel based on speaker position
            let speaker = speakers[0]
            switch speaker {
            case "FL":  return [0]      // Front Left → Channel 0
            case "FR":  return [1]      // Front Right → Channel 1
            case "FC":  return [2]      // Front Center → Channel 2
            case "LFE": return [3]      // LFE → Channel 3
            case "SL":  return [4]      // Side Left → Channel 4
            case "SR":  return [5]      // Side Right → Channel 5
            case "BL":  return [6]      // Back Left → Channel 6
            case "BR":  return [7]      // Back Right → Channel 7
            case "WL":  return [8]     // Wide Left → Channel 8
            case "WR":  return [9]     // Wide Right → Channel 9
            case "TFL": return [10]      // Top Front Left → Channel 8
            case "TFR": return [11]      // Top Front Right → Channel 9
            case "TML": return [12]     // Top Middle Left → Channel 10
            case "TMR": return [13]     // Top Middle Right → Channel 11
            case "TBL": return [14]     // Top Back Left → Channel 12
            case "TBR": return [15]     // Top Back Right → Channel 13
            default:    return [0]      // Unknown speaker → Channel 0
            }
            
        } else if speakers.count == 2 {
            // Stereo pair - map each speaker to its correct channel
            var channels: [Int] = []
            for speaker in speakers {
                let speakerChannels = mapSpeakersToChannels([speaker])
                channels.append(contentsOf: speakerChannels)
            }
            return channels.sorted()
            
        } else {
            // Multi-speaker group (3+ speakers) - map each individually
            var allChannels: [Int] = []
            for speaker in speakers {
                let speakerChannels = mapSpeakersToChannels([speaker])
                allChannels.append(contentsOf: speakerChannels)
            }
            // Remove duplicates and sort
            return Array(Set(allChannels)).sorted()
        }
    }
    
    /// Device compatibility fallback method
    private func getOutputChannelsForGroupWithDeviceCheck(
        _ group: SpeakerGroup,
        maxDeviceChannels: Int,
        channelMapping: ChannelMapping? = nil
    ) -> [Int] {
        // Get ideal channel mapping
        let idealChannels = getOutputChannelsForGroup(group, channelMapping: channelMapping)
        
        // Check if device supports all required channels
        let maxRequiredChannel = idealChannels.max() ?? 0
        if maxRequiredChannel < maxDeviceChannels {
            return idealChannels
        }
        
        // Fallback to stereo if device doesn't have enough channels
        print("⚠️ Layout requires channel \(maxRequiredChannel) but device only has \(maxDeviceChannels) channels. Falling back to stereo for group: \(group.speakers)")
        
        if group.speakers.count == 1 {
            let speaker = group.speakers[0]
            // Map single speakers to left/right based on typical position
            switch speaker {
            case "FL", "SL", "BL", "TFL", "TBL", "TML":
                return [0]  // Left-side speakers → Left channel
            case "FR", "SR", "BR", "TFR", "TBR", "TMR":
                return [1]  // Right-side speakers → Right channel
            case "FC", "LFE", "TC", "BC":
                return [0, 1]  // Center speakers → Both channels
            default:
                return [0, 1]  // Unknown → Both channels
            }
        } else {
            // Multi-speaker groups default to stereo
            return [0, 1]
        }
    }
    
    /// Validate Layout For Device Selection
    func validateLayoutForDevice(
        layout: SpeakerLayout,
        outputDevice: AudioDevice,
        channelMapping: ChannelMapping?
    ) -> (warnings: [String], canRecord: Bool) {
        var warnings: [String] = []
        var canRecord = true
        
        let maxDeviceChannels = outputDevice.maxOutputChannels
        
        // Basic device check
        if !outputDevice.canPlayback {
            warnings.append("Selected output device cannot play audio")
            canRecord = false
        }
        
        if maxDeviceChannels < 2 {
            warnings.append("Output device must have at least 2 channels for recording")
            canRecord = false
        }
        
        // Check each group in the layout
        for group in layout.groups {
            let idealChannels = getOutputChannelsForGroup(group, channelMapping: channelMapping)
            let maxRequiredChannel = idealChannels.max() ?? 0
            
            if maxRequiredChannel >= maxDeviceChannels {
                warnings.append("Group '\(group.name)' requires channel \(maxRequiredChannel + 1) but device only has \(maxDeviceChannels)")
                // Don't prevent recording - will fall back to stereo
            }
        }
        
        return (warnings: warnings, canRecord: canRecord)
    }
    
    /// Validate test signals for layout
    func validateTestSignalsForLayout(_ layout: SpeakerLayout) -> [String] {
        var missingSignals: [String] = []
        
        for group in layout.groups {
            // Basic validation - check if we have test signals
            if group.speakers.isEmpty {
                missingSignals.append(group.name)
            }
            // Add more sophisticated test signal validation here later
        }
        
        return missingSignals
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
    
    /// Get channel group pairing
    func getEffectiveChannelsForGroup(
        _ group: SpeakerGroup,
        maxDeviceChannels: Int,
        channelMapping: ChannelMapping?
    ) -> [Int] {
        let idealChannels = getOutputChannelsForGroup(group, channelMapping: channelMapping)
        let maxRequiredChannel = idealChannels.max() ?? 0
        
        // If device supports all required channels, use ideal mapping
        if maxRequiredChannel < maxDeviceChannels {
            return idealChannels
        }
        
        // Otherwise, fall back to stereo mapping
        print("⚠️ Falling back to stereo for group \(group.name) due to device channel limits")
        return getFallbackChannelsForGroup(group)
    }

    private func getFallbackChannelsForGroup(_ group: SpeakerGroup) -> [Int] {
        if group.speakers.count == 1 {
            let speaker = group.speakers[0]
            switch speaker {
            case "FL", "SL", "BL", "TFL", "TBL", "TML", "WL":
                return [0]  // Left-side speakers → Left channel
            case "FR", "SR", "BR", "TFR", "TBR", "TMR", "WR":
                return [1]  // Right-side speakers → Right channel
            case "FC", "LFE":
                return [0, 1]  // Center speakers → Both channels
            default:
                return [0, 1]  // Unknown → Both channels
            }
        } else {
            return [0, 1]  // Multi-speaker groups default to stereo
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

// MARK: - RecordingViewModel.swift Integration
// Add these methods to your existing RecordingViewModel

extension RecordingViewModel {
    
    // MARK: - Layout-Based Recording Methods
    
    /// Start recording with layout from LayoutManager
    func startLayoutBasedRecording(
        layout: SpeakerLayout,
        measurementDir: String,
        testSignal: String,
        inputDevice: AudioDevice,
        outputDevice: AudioDevice,
        channelMapping: ChannelMapping?
    ) {
        // Validate layout against device capabilities first
        let layoutErrors = validateLayoutForRecording(layout, outputDevice: outputDevice)
        if !layoutErrors.isEmpty {
            recordingState = .error("Layout validation failed: \(layoutErrors.joined(separator: ", "))")
            return
        }
        
        let baseConfig = RecordingConfiguration(
            measurementDir: measurementDir,
            testSignal: testSignal,
            playbackDevice: outputDevice.name,
            recordingDevice: inputDevice.name,
            outputFile: nil,
            speakerLayout: layout.name,
            recordingGroup: nil,
            outputChannels: nil,
            inputChannels: [0, 1]
        )
        
        if layout.groups.count == 1 {
            // Single group recording
            startSingleGroupRecording(layout: layout, baseConfig: baseConfig, channelMapping: channelMapping)
        } else {
            // Multi-group sequential recording
            startMultiGroupRecording(layout: layout, baseConfig: baseConfig, channelMapping: channelMapping)
        }
    }
    
    /// Start standard recording for non-measurement types
    func startStandardRecording(
        type: RecordingType,
        measurementDir: String,
        testSignal: String,
        outputFile: String,
        inputDevice: AudioDevice,
        outputDevice: AudioDevice
    ) {
        // Check recording type and configure accordingly
        let isRoomRecording = (type == .roomResponse)
        
        let configuration = RecordingConfiguration(
            measurementDir: measurementDir,
            testSignal: testSignal,
            playbackDevice: outputDevice.name,
            recordingDevice: inputDevice.name,
            outputFile: outputFile,
            speakerLayout: nil,
            recordingGroup: nil,
            outputChannels: isRoomRecording ? nil : [0, 1],
            inputChannels: isRoomRecording ? [0] : [0, 1]
        )
        
        startRecording(with: configuration)
    }
    
    // MARK: - Private Recording Methods
    
    private func startSingleGroupRecording(
        layout: SpeakerLayout,
        baseConfig: RecordingConfiguration,
        channelMapping: ChannelMapping?
    ) {
        let group = layout.groups[0]
        let outputChannels = getOutputChannelsForGroup(group, channelMapping: channelMapping)
        let fileName = "\(group.speakers.joined(separator: ",")).wav"
        let outputPath = "\(baseConfig.measurementDir)/\(fileName)"
        
        let groupConfig = RecordingConfiguration(
            measurementDir: baseConfig.measurementDir,
            testSignal: baseConfig.testSignal,
            playbackDevice: baseConfig.playbackDevice,
            recordingDevice: baseConfig.recordingDevice,
            outputFile: outputPath,
            speakerLayout: baseConfig.speakerLayout,
            recordingGroup: group.name,
            outputChannels: outputChannels,
            inputChannels: baseConfig.inputChannels
        )
        
        startRecording(with: groupConfig)
    }
    
    private func startMultiGroupRecording(
        layout: SpeakerLayout,
        baseConfig: RecordingConfiguration,
        channelMapping: ChannelMapping?
    ) {
        // Store configuration for sequential recording
        currentRecordingConfiguration = baseConfig
        remainingGroups = layout.groups
        
        // Initialize sequential state
        sequentialState = .preparing(totalGroups: layout.groups.count)
        
        // Start with first group
        startNextSequentialGroup(channelMapping: channelMapping)
    }
    
    private func startNextSequentialGroup(channelMapping: ChannelMapping?) {
        guard let baseConfig = currentRecordingConfiguration,
              !remainingGroups.isEmpty else {
            completeSequentialRecording()
            return
        }
        
        let currentGroup = remainingGroups.removeFirst()
        let groupIndex = getGroupIndex(for: currentGroup)
        let totalGroups = getTotalGroupCount()
        
        sequentialState = .recordingGroup(
            currentGroup: groupIndex,
            totalGroups: totalGroups,
            groupName: currentGroup.name
        )
        
        // Use basic channel mapping
        let outputChannels = getOutputChannelsForGroup(currentGroup, channelMapping: channelMapping)
        let fileName = "\(currentGroup.speakers.joined(separator: ",")).wav"
        let outputPath = "\(baseConfig.measurementDir)/\(fileName)"
        
        let groupConfig = RecordingConfiguration(
            measurementDir: baseConfig.measurementDir,
            testSignal: baseConfig.testSignal,
            playbackDevice: baseConfig.playbackDevice,
            recordingDevice: baseConfig.recordingDevice,
            outputFile: outputPath,
            speakerLayout: baseConfig.speakerLayout,
            recordingGroup: currentGroup.name,
            outputChannels: outputChannels,
            inputChannels: baseConfig.inputChannels
        )
        
        startRecording(with: groupConfig)
    }
    
    private func completeSequentialRecording() {
        sequentialState = .completed
        recordingState = .completed(outputFile: "Sequential recording completed") // Add the required String parameter
        currentRecordingConfiguration = nil
        remainingGroups = []
        
        // Notify completion
        NotificationCenter.default.post(
            name: .sequentialRecordingCompleted,
            object: nil
        )
    }
    
    // MARK: - Validation Methods
    
    func validateLayoutForRecording(_ layout: SpeakerLayout, outputDevice: AudioDevice) -> [String] {
        var errors: [String] = []
        
        // Check if device has enough output channels
        let requiredChannels = layout.totalSpeakers
        if outputDevice.maxOutputChannels < requiredChannels {
            errors.append("Layout requires \(requiredChannels) channels but device only has \(outputDevice.maxOutputChannels)")
        }
        
        // Check for empty groups
        for group in layout.groups {
            if group.speakers.isEmpty {
                errors.append("Group '\(group.name)' has no speakers")
            }
        }
        
        // Check for valid speaker names (basic validation)
        let validSpeakerPattern = "^[A-Z]{1,3}$"
        for group in layout.groups {
            for speaker in group.speakers {
                if speaker.range(of: validSpeakerPattern, options: .regularExpression) == nil {
                    errors.append("Invalid speaker name: \(speaker)")
                }
            }
        }
        
        return errors
    }
    
    // MARK: - Helper Methods
    
    private func getGroupIndex(for group: SpeakerGroup) -> Int {
        // Calculate current group index based on remaining groups
        return getTotalGroupCount() - remainingGroups.count
    }
    
    private func getTotalGroupCount() -> Int {
        // Use LayoutManager directly
        return LayoutManager.shared.getCurrentLayout()?.groups.count ?? remainingGroups.count + 1
    }
    
    // MARK: - Recording State Management
    
    func handleRecordingCompletion() {
        // If we're in sequential recording mode, start next group
        if sequentialState != .idle && !remainingGroups.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startNextSequentialGroup(channelMapping: nil)
            }
        }
    }
}

// MARK: - Additional Notification Names
extension Notification.Name {
    static let sequentialRecordingCompleted = Notification.Name("sequentialRecordingCompleted")
    static let recordingGroupChanged = Notification.Name("recordingGroupChanged")
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
