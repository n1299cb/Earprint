import Foundation
#if canImport(SwiftUI)
import SwiftUI

@MainActor
final class ModernProcessingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var log: String = ""
    @Published var isRunning: Bool = false
    @Published var progress: Double? = nil
    @Published var remainingTime: Double? = nil
    @Published var autoLog: Bool = false
    @Published var logFile: String = ""
    
    // MARK: - Processing State
    @Published var currentOperation: ProcessingOperation = .idle
    @Published var errorMessage: String? = nil
    @Published var hasError: Bool = false
    
    // MARK: - Private Properties
    private var process: Process?
    private var logUpdateTimer: Timer?
    private var pipe: Pipe?
    
    enum ProcessingOperation: String, CaseIterable {
        case idle = "Idle"
        case recording = "Recording"
        case processing = "Processing"
        case layoutGeneration = "Layout Generation"
        case captureWizard = "Capture Wizard"
        case headphoneEQ = "Headphone EQ"
        case roomResponse = "Room Response"
        case export = "Export"
        
        var displayName: String { rawValue }
        
        var icon: String {
            switch self {
            case .idle: return "pause.circle"
            case .recording: return "record.circle"
            case .processing: return "waveform"
            case .layoutGeneration: return "speaker.wave.3"
            case .captureWizard: return "wand.and.stars"
            case .headphoneEQ: return "headphones"
            case .roomResponse: return "house.and.flag"
            case .export: return "square.and.arrow.up"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        setupLogTimer()
    }
    
    deinit {
        // Cleanup synchronously to avoid capture issues
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        // Note: Timer cleanup handled in cleanup() method due to MainActor isolation
    }
    
    // MARK: - Public Methods
    
    func run(measurementDir: String,
             testSignal: String,
             channelBalance: String?,
             targetLevel: String?,
             playbackDevice: String?,
             recordingDevice: String?,
             outputChannels: [Int]?,
             inputChannels: [Int]?,
             enableCompensation: Bool,
             headphoneEqEnabled: Bool,
             headphoneFile: String?,
             compensationType: String?,
             diffuseField: Bool,
             xCurveAction: String,
             xCurveType: String?,
             xCurveInCapture: Bool,
             decayTime: String,
             decayEnabled: Bool,
             specificLimit: String,
             specificLimitEnabled: Bool,
             genericLimit: String,
             genericLimitEnabled: Bool,
             frCombinationMethod: String,
             frCombinationEnabled: Bool,
             roomCorrection: Bool,
             roomTarget: String,
             micCalibration: String,
             interactiveDelays: Bool) {
        
        guard !isRunning else {
            appendError("Cannot start processing: another operation is already running")
            return
        }
        
        currentOperation = .processing
        
        var args = ["--dir_path", measurementDir, "--test_signal", testSignal]
        
        // Build arguments array
        if let balance = channelBalance, !balance.isEmpty {
            args += ["--channel_balance", balance]
        }
        if let target = targetLevel, !target.isEmpty {
            args += ["--target_level", target]
        }
        if decayEnabled, !decayTime.isEmpty {
            args += ["--decay", decayTime]
        }
        if let p = playbackDevice {
            args += ["--playback_device", p]
        }
        if let r = recordingDevice {
            args += ["--recording_device", r]
        }
        if let outs = outputChannels, !outs.isEmpty {
            args += ["--output_channels", outs.map(String.init).joined(separator: ",")]
        }
        if let ins = inputChannels, !ins.isEmpty {
            args += ["--input_channels", ins.map(String.init).joined(separator: ",")]
        }
        
        // Room correction arguments
        if roomCorrection {
            args.append("--room_target")
            args.append(roomTarget)
            if !micCalibration.isEmpty {
                args += ["--room_mic_calibration", micCalibration]
            }
            if specificLimitEnabled, !specificLimit.isEmpty {
                args += ["--specific_limit", specificLimit]
            }
            if genericLimitEnabled, !genericLimit.isEmpty {
                args += ["--generic_limit", genericLimit]
            }
            if frCombinationEnabled {
                args += ["--fr_combination_method", frCombinationMethod]
            }
        }
        
        // Compensation arguments
        if enableCompensation {
            args.append("--compensation")
            if headphoneEqEnabled {
                if let file = headphoneFile, !file.isEmpty {
                    args += ["--headphones", file]
                }
            } else {
                args.append("--no_headphone_compensation")
            }
            if let cType = compensationType, !cType.isEmpty {
                args.append(cType)
            }
        }
        
        // Additional processing options
        if xCurveAction == "Apply X-Curve" {
            args.append("--apply_x_curve")
        }
        if xCurveAction == "Remove X-Curve" {
            args.append("--remove_x_curve")
        }
        if xCurveAction != "None", let ct = xCurveType, !ct.isEmpty {
            args += ["--x_curve_type", ct]
        }
        if xCurveInCapture {
            args.append("--x_curve_in_capture")
        }
        
        // Delay handling
        if interactiveDelays {
            args.append("--interactive_delays")
        } else {
            let posFile = URL(fileURLWithPath: measurementDir).appendingPathComponent("speaker_positions.json")
            if FileManager.default.fileExists(atPath: posFile.path) {
                let delayFile = URL(fileURLWithPath: measurementDir).appendingPathComponent("speaker_delays.json")
                args += ["--delay-file", delayFile.path]
            }
        }
        
        startPython(script: scriptPath("earprint.py"), args: args)
    }

    func layoutWizard(layout: String, dir: String) {
        guard !isRunning else {
            appendError("Cannot start layout wizard: another operation is already running")
            return
        }
        
        currentOperation = .layoutGeneration
        startPython(script: scriptPath("generate_layout.py"), args: ["--layout", layout, "--dir", dir])
    }

    func captureWizard(layout: String, dir: String) {
        guard !isRunning else {
            appendError("Cannot start capture wizard: another operation is already running")
            return
        }
        
        currentOperation = .captureWizard
        startPython(script: scriptPath("capture_wizard.py"), args: ["--layout", layout, "--dir", dir, "--print_progress"])
    }

    func record(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String, outputFile: String?) {
        guard !isRunning else {
            appendError("Cannot start recording: another operation is already running")
            return
        }
        
        currentOperation = .recording
        
        var args = [
            "--output_dir", measurementDir,
            "--test_signal", testSignal,
            "--playback_device", playbackDevice,
            "--recording_device", recordingDevice,
            "--print_progress"
        ]
        if let file = outputFile {
            args += ["--output_file", file]
        }
        startPython(script: scriptPath("recorder.py"), args: args)
    }

    func recordHeadphoneEQ(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {
        guard !isRunning else {
            appendError("Cannot start headphone EQ recording: another operation is already running")
            return
        }
        
        currentOperation = .headphoneEQ
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent("headphones.wav").path
        record(measurementDir: measurementDir,
               testSignal: testSignal,
               playbackDevice: playbackDevice,
               recordingDevice: recordingDevice,
               outputFile: file)
    }

    func recordRoomResponse(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {
        guard !isRunning else {
            appendError("Cannot start room response recording: another operation is already running")
            return
        }
        
        currentOperation = .roomResponse
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent("room.wav").path
        record(measurementDir: measurementDir,
               testSignal: testSignal,
               playbackDevice: playbackDevice,
               recordingDevice: recordingDevice,
               outputFile: file)
    }

    func exportHesuviPreset(measurementDir: String, destination: String) {
        guard !isRunning else {
            appendError("Cannot export: another operation is already running")
            return
        }
        
        currentOperation = .export
        
        let src = URL(fileURLWithPath: measurementDir).appendingPathComponent("hesuvi.wav")
        let dest = URL(fileURLWithPath: destination)
        
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            appendLog("Exported to \(destination)\n")
            currentOperation = .idle
        } catch {
            appendError("Export failed: \(error.localizedDescription)")
        }
    }

    func clearLog() {
        log = ""
        errorMessage = nil
        hasError = false
    }

    func cancel() {
        guard isRunning else { return }
        
        process?.terminate()
        cleanup()
        appendLog("Operation cancelled by user\n")
    }
    
    // MARK: - Logging
    
    func logMessage(_ text: String) {
        appendLog(text)
    }
    
    // MARK: - Private Methods
    
    private func startPython(script: String, args: [String]) {
        isRunning = true
        progress = nil
        remainingTime = nil
        errorMessage = nil
        hasError = false
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
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
                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                
                Task { @MainActor in
                    self.handleProcessOutput(str)
                }
            }
            
            do {
                Task { @MainActor in
                    self.process = process
                    self.pipe = pipe
                }
                try process.run()
                process.waitUntilExit()
            } catch {
                Task { @MainActor in
                    self.appendError("Process failed to start: \(error.localizedDescription)")
                }
            }
            
            Task { @MainActor in
                self.cleanup()
            }
        }
    }
    
    private func handleProcessOutput(_ output: String) {
        if output.hasPrefix("PROGRESS") {
            let components = output.split(separator: " ")
            if components.count >= 2, let val = Double(components[1]) {
                progress = val
            }
            if components.count >= 3, let rem = Double(components[2]) {
                remainingTime = rem
            }
        } else if output.lowercased().contains("error") {
            appendError(output)
        } else {
            appendLog(output)
        }
    }
    
    private func appendLog(_ text: String) {
        log += text
        
        // Auto-save to file if enabled
        if autoLog, !logFile.isEmpty {
            saveLogToFile(text)
        }
    }
    
    private func appendError(_ text: String) {
        errorMessage = text
        hasError = true
        appendLog("ERROR: \(text)\n")
    }
    
    private func saveLogToFile(_ text: String) {
        guard !logFile.isEmpty else { return }
        
        let url = URL(fileURLWithPath: logFile)
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    handle.write(data)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
    
    private func cleanup() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        process = nil
        logUpdateTimer?.invalidate()
        logUpdateTimer = nil
        isRunning = false
        progress = nil
        remainingTime = nil
        currentOperation = .idle
    }
    
    private func setupLogTimer() {
        // Optional: Add periodic log cleanup or other maintenance
        logUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Could add log rotation, cleanup, etc.
        }
    }
}

// MARK: - Helper Properties
extension ModernProcessingViewModel {
    var canStartNewOperation: Bool {
        !isRunning
    }
    
    var statusText: String {
        if isRunning {
            return "\(currentOperation.displayName)..."
        } else if hasError {
            return "Error occurred"
        } else {
            return "Ready"
        }
    }
    
    var statusColor: Color {
        if isRunning {
            return .blue
        } else if hasError {
            return .red
        } else {
            return .green
        }
    }
}

#else
// Fallback for non-SwiftUI environments
final class ModernProcessingViewModel {
    var log: String = ""
    var isRunning: Bool = false
    var progress: Double? = nil
    var remainingTime: Double? = nil
    var autoLog: Bool = false
    var logFile: String = ""
    var currentOperation: String = "Idle"
    var errorMessage: String? = nil
    var hasError: Bool = false
    
    func run(measurementDir: String, testSignal: String, channelBalance: String?, targetLevel: String?, playbackDevice: String?, recordingDevice: String?, outputChannels: [Int]?, inputChannels: [Int]?, enableCompensation: Bool, headphoneEqEnabled: Bool, headphoneFile: String?, compensationType: String?, diffuseField: Bool, xCurveAction: String, xCurveType: String?, xCurveInCapture: Bool, decayTime: String, decayEnabled: Bool, specificLimit: String, specificLimitEnabled: Bool, genericLimit: String, genericLimitEnabled: Bool, frCombinationMethod: String, frCombinationEnabled: Bool, roomCorrection: Bool, roomTarget: String, micCalibration: String, interactiveDelays: Bool) {}
    func layoutWizard(layout: String, dir: String) {}
    func captureWizard(layout: String, dir: String) {}
    func record(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String, outputFile: String?) {}
    func recordHeadphoneEQ(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {}
    func recordRoomResponse(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {}
    func exportHesuviPreset(measurementDir: String, destination: String) {}
    func clearLog() {}
    func cancel() {}
    func logMessage(_ text: String) {}
}
#endif
