#if canImport(SwiftUI)
import SwiftUI
#if canImport(CoreAudio)
import CoreAudio
#endif
import AppKit

struct SetupView: View {
    @ObservedObject var viewModel: ProcessingViewModel
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
        VStack(alignment: .leading) {
            Form {
                HStack {
                    Text("Latest Recording:")
                    TextField("No recordings", text: $recordingVM.recordingName)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Save…") {
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
                    .disabled(!recordingVM.measurementHasFiles)
                }
            HStack {
                TextField("Test signal", text: $testSignal)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(testSignalValid ? Color.green : Color.red))
                    .onChange(of: testSignal) { _ in validatePaths() }
                Button("Browse") {
                    if let path = openPanel(directory: false, startPath: testSignal) {
                        testSignal = path
                    }
                }
            }
            Picker("Playback Device", selection: $playbackDevice) {
                ForEach(playbackDevices) { dev in
                    Text("\(dev.name) (\(dev.maxInput) in / \(dev.maxOutput) out)")
                        .tag(String(dev.id))
                }
            }
            Picker("Recording Device", selection: $recordingDevice) {
                ForEach(recordingDevices) { dev in
                    Text("\(dev.name) (\(dev.maxInput) in / \(dev.maxOutput) out)")
                        .tag(String(dev.id))
                }
            }
            Picker("Layout", selection: $selectedLayout) {
                ForEach(layouts, id: \.self) { Text($0) }
            }
            HStack {
                Spacer()
                Button("Refresh Devices") { loadDevices() }
            }
            TextField("Channel Balance", text: $channelBalance)
            TextField("Target Level", text: $targetLevel)
            HStack {
                Button("Layout Wizard") {
                    viewModel.layoutWizard(layout: selectedLayout, dir: measurementDir)
                }
                Button("Map Channels") {
                    if fetchSpeakerLabels(layout: selectedLayout).isEmpty {
                        viewModel.log += "No speaker labels found for layout \(selectedLayout).\n"
                    } else {
                        showMapping = true
                    }
                }
                Button("Auto Map") { autoMapChannels() }
            }
            if !channelWarning.isEmpty {
                Text(channelWarning)
                    .foregroundColor(.red)
            }
            HStack {
                Text("Input Level")
                ProgressView(value: inputLevel)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                Button(isMonitoring ? "Stop Monitor" : "Start Monitor") {
                    isMonitoring ? stopMonitor() : startMonitor()
                }
            }
            HStack {
                Text("Output Level")
                ProgressView(value: outputLevel)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
            }
            if viewModel.isRunning {
                if let progress = viewModel.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            if !viewModel.log.isEmpty {
                ScrollView {
                    Text(viewModel.log)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .onAppear(perform: loadLayouts)
        .onAppear(perform: loadDevices)
        .onAppear(perform: validatePaths)
        .onAppear(perform: validateChannelCount)
        .onChange(of: measurementDir) { _ in validatePaths() }
        .onChange(of: selectedLayout) { _ in validateChannelCount() }
        .onChange(of: playbackDevice) { _ in validateChannelCount() }
        .onChange(of: recordingDevice) { _ in validateChannelCount() }
        .sheet(isPresented: $showMapping, content: {
            mappingSheet
        })
        .alert("Error", isPresented: $recordingVM.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recordingVM.errorMessage)
        }
    }
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

    // openPanel and scriptPath helpers are provided by Utilities.swift

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

    func loadLayouts() {
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
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                DispatchQueue.main.async {
                    self.layouts = arr
                    if self.selectedLayout.isEmpty, let first = arr.first {
                        self.selectedLayout = first
                    }
                    self.validateChannelCount()
                }
            } else {
                DispatchQueue.main.async {
                    self.viewModel.log += String(data: data, encoding: .utf8) ?? "Failed to load layouts\n"
                }
            }
        }
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

    var mappingSheet: some View {
        let pChannels = playbackDevices.first(where: { String($0.id) == playbackDevice })?.maxOutput ?? 2
        let rChannels = recordingDevices.first(where: { String($0.id) == recordingDevice })?.maxInput ?? 2
        let labels = fetchSpeakerLabels(layout: selectedLayout)
        return ChannelMappingView(
            playbackChannels: pChannels,
            recordingChannels: rChannels,
            speakerLabels: labels,
            playbackDevice: playbackDevice,
            channelMapping: $channelMapping,
            isPresented: $showMapping
        )
        .frame(minWidth: 300, minHeight: 200)
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
#endif
