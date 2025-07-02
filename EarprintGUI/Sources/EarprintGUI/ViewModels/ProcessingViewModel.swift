import Foundation
#if canImport(SwiftUI)
import SwiftUI

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published var log: String = ""
    @Published var isRunning: Bool = false
    @Published var progress: Double? = nil
    @Published var remainingTime: Double? = nil
    @Published var autoLog: Bool = false
    @Published var logFile: String = ""

    private var process: Process?
    
    // scriptPath helper provided by Utilities.swift

    private func startPython(script: String, args: [String]) {
        isRunning = true
        progress = nil
        remainingTime = nil
        log = ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
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
                guard let self else { return }
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    if str.hasPrefix("PROGRESS") {
                        let comps = str.split(separator: " ")
                        if comps.count >= 2, let val = Double(comps[1]) {
                            self.progress = val
                        }
                        if comps.count >= 3, let rem = Double(comps[2]) {
                            self.remainingTime = rem
                        }
                    } else {
                        self.appendLog(str)
                    }
                }
            }
            do {
                Task { @MainActor in self.process = process }
                try process.run()
                process.waitUntilExit()
            } catch {
                Task { @MainActor in
                    self.appendLog("\(error)\n")
                }
            }
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self.isRunning = false
                self.progress = nil
                self.remainingTime = nil
                self.process = nil
            }
        }
    }

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
        var args = ["--dir_path", measurementDir, "--test_signal", testSignal]
        if let balance = channelBalance, !balance.isEmpty {
            args += ["--channel_balance", balance]
        }
        if let target = targetLevel, !target.isEmpty {
            args += ["--target_level", target]
        }
        if decayEnabled, !decayTime.isEmpty { args += ["--decay", decayTime] }
        if let p = playbackDevice { args += ["--playback_device", p] }
        if let r = recordingDevice { args += ["--recording_device", r] }
        if let outs = outputChannels, !outs.isEmpty {
            args += ["--output_channels", outs.map(String.init).joined(separator: ",")] 
        }
        if let ins = inputChannels, !ins.isEmpty {
            args += ["--input_channels", ins.map(String.init).joined(separator: ",")] 
        }
        if roomCorrection {
            args.append("--room_target")
            args.append(roomTarget)
            if !micCalibration.isEmpty { args += ["--room_mic_calibration", micCalibration] }
            if specificLimitEnabled, !specificLimit.isEmpty { args += ["--specific_limit", specificLimit] }
            if genericLimitEnabled, !genericLimit.isEmpty { args += ["--generic_limit", genericLimit] }
            if frCombinationEnabled { args += ["--fr_combination_method", frCombinationMethod] }
        }
        if enableCompensation {
            args.append("--compensation")
            if headphoneEqEnabled {
                if let file = headphoneFile, !file.isEmpty { args += ["--headphones", file] }
            } else {
                args.append("--no_headphone_compensation")
            }
            if let cType = compensationType, !cType.isEmpty { args.append(cType) }
        }
        if diffuseField { args.append("--diffuse_field_compensation") }
        if xCurveAction == "Apply X-Curve" { args.append("--apply_x_curve") }
        if xCurveAction == "Remove X-Curve" { args.append("--remove_x_curve") }
        if xCurveAction != "None", let ct = xCurveType, !ct.isEmpty {
            args += ["--x_curve_type", ct]
        }
        if xCurveInCapture { args.append("--x_curve_in_capture") }
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
        startPython(script: scriptPath("generate_layout.py"), args: ["--layout", layout, "--dir", dir])
    }

    func captureWizard(layout: String, dir: String) {
        startPython(script: scriptPath("capture_wizard.py"), args: ["--layout", layout, "--dir", dir, "--print_progress"])
    }

    func record(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String, outputFile: String?) {
        var args = [
            "--output_dir", measurementDir,
            "--test_signal", testSignal,
            "--playback_device", playbackDevice,
            "--recording_device", recordingDevice,
            "--print_progress"
        ]
        if let file = outputFile { args += ["--output_file", file] }
        startPython(script: scriptPath("recorder.py"), args: args)
    }

    func recordHeadphoneEQ(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent("headphones.wav").path
        record(measurementDir: measurementDir,
               testSignal: testSignal,
               playbackDevice: playbackDevice,
               recordingDevice: recordingDevice,
               outputFile: file)
    }

    func recordRoomResponse(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent("room.wav").path
        record(measurementDir: measurementDir,
               testSignal: testSignal,
               playbackDevice: playbackDevice,
               recordingDevice: recordingDevice,
               outputFile: file)
    }

    func exportHesuviPreset(measurementDir: String, destination: String) {
        let src = URL(fileURLWithPath: measurementDir).appendingPathComponent("hesuvi.wav")
        let dest = URL(fileURLWithPath: destination)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            appendLog("Exported to \(destination)\n")
        } catch {
            appendLog("Export failed: \(error)\n")
        }
    }

    private func appendLog(_ text: String) {
        log += text
        guard autoLog, !logFile.isEmpty else { return }
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

    func clearLog() {
        log = ""
    }

    func cancel() {
        process?.terminate()
        process = nil
        isRunning = false
        progress = nil
    }
}
#else
final class ProcessingViewModel {
    var log: String = ""
    var isRunning: Bool = false
    var progress: Double? = nil
    var remainingTime: Double? = nil
    var autoLog: Bool = false
    var logFile: String = ""
    func run(measurementDir: String, testSignal: String, channelBalance: String?, targetLevel: String?, playbackDevice: String?, recordingDevice: String?, outputChannels: [Int]?, inputChannels: [Int]?, enableCompensation: Bool, headphoneEqEnabled: Bool, headphoneFile: String?, compensationType: String?, diffuseField: Bool, xCurveAction: String, xCurveType: String?, xCurveInCapture: Bool, decayTime: String, decayEnabled: Bool, specificLimit: String, specificLimitEnabled: Bool, genericLimit: String, genericLimitEnabled: Bool, frCombinationMethod: String, frCombinationEnabled: Bool, roomCorrection: Bool, roomTarget: String, micCalibration: String, interactiveDelays: Bool) {}
    func layoutWizard(layout: String, dir: String) {}
    func captureWizard(layout: String, dir: String) {}
    func record(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String, outputFile: String?) {}
    func recordHeadphoneEQ(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {}
    func recordRoomResponse(measurementDir: String, testSignal: String, playbackDevice: String, recordingDevice: String) {}
    func exportHesuviPreset(measurementDir: String, destination: String) {}
    func clearLog() {}
    func cancel() {}
}
#endif