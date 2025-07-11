#if canImport(SwiftUI)
import SwiftUI
import Foundation
import Combine

// MARK: - Enhanced ProcessingViewModel
@MainActor
final class ProcessingViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var state: ProcessingState = .idle
    @Published var log: String = ""
    @Published var autoLog: Bool = false
    @Published var logFile: String = ""
    
    // MARK: - Computed Properties
    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }
    
    var progress: Double? {
        if case .running(let progress, _) = state { return progress }
        return nil
    }
    
    var remainingTime: Double? {
        if case .running(_, let time) = state { return time }
        return nil
    }
    
    // MARK: - Private Properties
    private var process: Process?
    private var progressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupLogBinding()
    }
    
    // MARK: - Public Methods
    func run(configuration: ProcessingConfiguration) {
        guard !isRunning else { return }
        
        do {
            try validateConfiguration(configuration)
            state = .running(progress: nil, remainingTime: nil)
            startProcessing(with: configuration)
        } catch {
            state = .failed(error)
            logMessage("Configuration error: \(error.localizedDescription)")
        }
    }
    
    func layoutWizard(layout: String, dir: String) {
        guard !isRunning else { return }
        
        state = .running(progress: nil, remainingTime: nil)
        let args = ["--layout", layout, "--dir", dir]
        startPython(script: scriptPath("generate_layout.py"), args: args)
    }
    
    func captureWizard(layout: String, dir: String) {
        guard !isRunning else { return }
        
        state = .running(progress: nil, remainingTime: nil)
        let args = ["--layout", layout, "--dir", dir]
        startPython(script: scriptPath("capture_wizard.py"), args: args)
    }
    
    func exportHesuviPreset(from measurementDir: String, to destination: String) {
        let src = URL(fileURLWithPath: measurementDir).appendingPathComponent("hesuvi.wav")
        let dest = URL(fileURLWithPath: destination)
        
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            logMessage("Exported to \(destination)")
        } catch {
            logMessage("Export failed: \(error.localizedDescription)")
            state = .failed(error)
        }
    }
    
    func cancel() {
        process?.terminate()
        process = nil
        progressTimer?.invalidate()
        progressTimer = nil
        state = .idle
    }
    
    func clearLog() {
        log = ""
    }
    
    func logMessage(_ text: String) {
        appendLog(text + "\n")
    }
    
    // MARK: - Private Methods
    private func setupLogBinding() {
        $log
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] newLog in
                self?.writeLogToFile(newLog)
            }
            .store(in: &cancellables)
    }
    
    private func validateConfiguration(_ config: ProcessingConfiguration) throws {
        guard !config.measurementDir.isEmpty else {
            throw ProcessingError.invalidMeasurementDirectory
        }
        
        guard !config.testSignal.isEmpty else {
            throw ProcessingError.invalidTestSignal
        }
        
        if config.roomCorrection && !config.micCalibration.isEmpty {
            let calibrationURL = URL(fileURLWithPath: config.micCalibration)
            guard FileManager.default.fileExists(atPath: calibrationURL.path) else {
                throw ProcessingError.missingCalibrationFile(config.micCalibration)
            }
        }
        
        if config.headphoneEqEnabled, let file = config.headphoneFile {
            let fileURL = URL(fileURLWithPath: file)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ProcessingError.missingHeadphoneFile(file)
            }
        }
    }
    
    private func startProcessing(with config: ProcessingConfiguration) {
        let args = buildProcessingArgs(config)
        startPython(script: scriptPath("earprint.py"), args: args)
    }
    
    private func buildProcessingArgs(_ config: ProcessingConfiguration) -> [String] {
        var args = [
            "--dir_path", config.measurementDir,
            "--print_progress"
        ]
        
        // Test signal - use --test_signal (not --input)
        // This points to the sweep file (e.g., sweep-6.15s-48000Hz-32bit-2.93Hz-24000Hz.pkl)
        if !config.testSignal.isEmpty {
            args += ["--test_signal", config.testSignal]
        }
        
        // Basic processing parameters
        if let balance = config.channelBalance, !balance.isEmpty {
            args += ["--channel_balance", balance]
        }
        if let level = config.targetLevel, !level.isEmpty {
            args += ["--target_level", level]
        }
        if let device = config.playbackDevice, !device.isEmpty {
            args += ["--playback_device", device]
        }
        if let device = config.recordingDevice, !device.isEmpty {
            args += ["--recording_device", device]
        }
        if let channels = config.outputChannels, !channels.isEmpty {
            args += ["--output_channels", channels.map(String.init).joined(separator: ",")]
        }
        if let channels = config.inputChannels, !channels.isEmpty {
            args += ["--input_channels", channels.map(String.init).joined(separator: ",")]
        }
        
        // Compensation settings - Fixed argument mapping
        if config.enableCompensation {
            args.append("--compensation")
            
            // Headphone compensation file
            if config.headphoneEqEnabled, let file = config.headphoneFile, !file.isEmpty {
                args += ["--headphones", file]
            }
            
            // Compensation type - use flag format instead of --compensation_type
            if let type = config.compensationType, !type.isEmpty {
                switch type {
                case "diffuse-field":
                    args.append("--diffuse_field_compensation")
                case "custom":
                    // Custom compensation files are handled via --headphones argument above
                    break
                default:
                    // Handle other compensation types if needed
                    break
                }
            }
        } else {
            // Explicitly disable headphone compensation
            args.append("--no_headphone_compensation")
        }
        
        // Diffuse field compensation (separate from compensation type)
        if config.diffuseField {
            args.append("--diffuse_field_compensation")
        }
        
        // X-Curve settings - Fixed argument mapping
        switch config.xCurveAction {
        case "Apply":
            args.append("--apply_x_curve")
        case "Remove":
            args.append("--remove_x_curve")
        default:
            // "None" - don't add any x-curve arguments
            break
        }
        
        if let type = config.xCurveType, !type.isEmpty && config.xCurveAction != "None" {
            args += ["--x_curve_type", type]
        }
        if config.xCurveInCapture {
            args.append("--x_curve_in_capture")
        }
        
        // Advanced processing parameters
        if config.decayEnabled, !config.decayTime.isEmpty {
            args += ["--decay", config.decayTime]
        }
        if config.specificLimitEnabled, !config.specificLimit.isEmpty {
            args += ["--specific_limit", config.specificLimit]
        }
        if config.genericLimitEnabled, !config.genericLimit.isEmpty {
            args += ["--generic_limit", config.genericLimit]
        }
        if config.frCombinationEnabled, !config.frCombinationMethod.isEmpty {
            args += ["--fr_combination_method", config.frCombinationMethod]
        }
        
        // Room correction settings - Fixed argument mapping
        if config.roomCorrection {
            if !config.roomTarget.isEmpty {
                args += ["--room_target", config.roomTarget]
            }
            if !config.micCalibration.isEmpty {
                args += ["--room_mic_calibration", config.micCalibration]
            }
        } else {
            args.append("--no_room_correction")
        }
        
        // Delay settings
        if config.interactiveDelays {
            args.append("--interactive_delays")
        }
        
        // Output settings
        if let sampleRate = config.outputSampleRate, !sampleRate.isEmpty {
            args += ["--fs", sampleRate]
        }
        if config.generatePlots {
            args.append("--plot")
        }
        if config.exportCSV {
            args.append("--csv")
        }
        
        return args
    }
    
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
                    self?.processOutput(output)
                }
            }
        }
        
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.processTerminated(with: process.terminationStatus)
            }
        }
        
        do {
            try process.run()
            self.process = process
            startProgressMonitoring()
        } catch {
            state = .failed(error)
            logMessage("Failed to start process: \(error.localizedDescription)")
        }
    }
    
    private func processOutput(_ output: String) {
        appendLog(output)
        parseProgressFromOutput(output)
    }
    
    private func parseProgressFromOutput(_ output: String) {
        // Parse progress indicators from Python output
        if let progressMatch = output.range(of: #"(\d+\.?\d*)%"#, options: .regularExpression) {
            let progressStr = String(output[progressMatch])
            if let progressValue = Double(progressStr.replacingOccurrences(of: "%", with: "")) {
                let normalizedProgress = progressValue / 100.0
                if case .running(_, let time) = state {
                    state = .running(progress: normalizedProgress, remainingTime: time)
                }
            }
        }
        
        // Parse time estimates if available
        if output.range(of: #"(\d+\.?\d*)\s*(?:min|sec|hour)s?\s*remaining"#, options: .regularExpression) != nil {
            // Time parsing implementation could go here
        }
    }
    
    private func processTerminated(with status: Int32) {
        progressTimer?.invalidate()
        progressTimer = nil
        process = nil
        
        if status == 0 {
            state = .completed
            logMessage("Process completed successfully")
        } else {
            let error = ProcessingError.processFailure(status)
            state = .failed(error)
            logMessage("Process failed with status: \(status)")
        }
    }
    
    private func startProgressMonitoring() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Update UI or check process status
        }
    }
    
    private func appendLog(_ text: String) {
        log += text
    }
    
    private func writeLogToFile(_ content: String) {
        guard autoLog, !logFile.isEmpty else { return }
        
        let url = URL(fileURLWithPath: logFile)
        guard let data = content.data(using: .utf8) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: logFile) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try data.write(to: url)
            }
        } catch {
            // Log writing failed, but don't interrupt main process
        }
    }
}

#else
// Non-macOS stub implementation
final class ProcessingViewModel {
    var state: ProcessingState = .idle
    var log: String = ""
    var autoLog: Bool = false
    var logFile: String = ""
    var isRunning: Bool { false }
    var progress: Double? { nil }
    var remainingTime: Double? { nil }
    
    func run(configuration: ProcessingConfiguration) {}
    func record(configuration: RecordingConfiguration) {}
    func recordHeadphoneEQ(configuration: RecordingConfiguration) {}
    func recordRoomResponse(configuration: RecordingConfiguration) {}
    func layoutWizard(layout: String, dir: String) {}
    func captureWizard(layout: String, dir: String) {}
    func exportHesuviPreset(from: String, to: String) {}
    func cancel() {}
    func clearLog() {}
    func logMessage(_ text: String) {}
}
#endif
