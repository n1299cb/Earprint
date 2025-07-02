#if canImport(SwiftUI)
import SwiftUI

struct ChannelMappingView: View {
    @Environment(\.dismiss) private var dismiss
    var playbackChannels: Int
    var recordingChannels: Int
    var playbackDevice: String
    var speakerLabels: [String]
    @Binding var channelMapping: [String: [Int]]
    @Binding var isPresented: Bool
    var onSave: () -> Void = {}

    private var mappingCompatible: Bool {
        playbackChannels >= speakerLabels.count && recordingChannels >= 2
    }

    private var channelWarning: String? {
        var warnings: [String] = []
        if playbackChannels < speakerLabels.count && !speakerLabels.isEmpty {
            warnings.append("Playback device only has \(playbackChannels) channels while layout requires \(speakerLabels.count).")
        }
        if recordingChannels < 2 {
            let suffix = recordingChannels == 1 ? "" : "s"
            warnings.append("Recording device only has \(recordingChannels) channel\(suffix); two are required.")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    @State private var speakerSelections: [Int]
    @State private var micSelections: [Int]
    @State private var useTone: Bool = true

    init(playbackChannels: Int,
         recordingChannels: Int,
         speakerLabels: [String],
         playbackDevice: String,
         channelMapping: Binding<[String: [Int]]>,
         isPresented: Binding<Bool>,
         onSave: @escaping () -> Void = {}) {
        self.playbackChannels = playbackChannels
        self.recordingChannels = recordingChannels
        self.speakerLabels = speakerLabels
        self.playbackDevice = playbackDevice
        self._channelMapping = channelMapping
        self._isPresented = isPresented
        self.onSave = onSave
        _speakerSelections = State(initialValue: channelMapping.wrappedValue["output_channels"] ?? Array(0..<speakerLabels.count))
        _micSelections = State(initialValue: channelMapping.wrappedValue["input_channels"] ?? [0, 1])
    }

    private var speakerSection: some View {
        Form {
            Section(header: Text("Speaker Channels")) {
                if speakerLabels.isEmpty {
                    Text("No speaker labels available").foregroundColor(.red)
                }
                Picker("Signal", selection: $useTone) {
                    Text("1 kHz Tone").tag(true)
                    Text("Pink Noise").tag(false)
                }
                .pickerStyle(SegmentedPickerStyle())
                ForEach(speakerLabels.indices, id: \.self) { idx in
                    Picker(speakerLabels[idx], selection: $speakerSelections[idx]) {
                        ForEach(0..<playbackChannels, id: \.self) { ch in
                            Text("\(ch + 1)").tag(ch)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    Button("Test") { playChannel(idx: speakerSelections[idx]) }
                }
            }
        }
    }

    private var microphoneSection: some View {
        Form {
            Section(header: Text("Microphone Channels")) {
                ForEach(0..<2, id: \.self) { idx in
                    Picker(idx == 0 ? "Mic Left" : "Mic Right", selection: $micSelections[idx]) {
                        ForEach(0..<recordingChannels, id: \.self) { ch in
                            Text("\(ch + 1)").tag(ch)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
        }
    }

    func playChannel(idx: Int) {
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        if let py = embeddedPythonURL {
            process.executableURL = py
            process.arguments = [
                scriptPath("channel_tester.py"),
                "--device", playbackDevice,
                "--channels", String(playbackChannels),
                "--channel", String(idx)
            ] + (useTone ? ["--tone"] : [])
            process.environment = [
                "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                "PYTHONPATH": scriptsRoot.path
            ]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var args = [
                "python3",
                scriptPath("channel_tester.py"),
                "--device", playbackDevice,
                "--channels", String(playbackChannels),
                "--channel", String(idx)
            ]
            if useTone { args.append("--tone") }
            process.arguments = args
        }
        try? process.run()
        process.waitUntilExit()
    }

    var body: some View {
        VStack {
            HStack {
                speakerSection
                microphoneSection
            }
            if let warning = channelWarning {
                Text(warning)
                    .foregroundColor(.red)
            }
            HStack {
                if channelWarning != nil {
                    Button("Close") {
                        isPresented = false
                        dismiss()
                    }
                }
                Button("Save") {
                    channelMapping["output_channels"] = speakerSelections
                    channelMapping["input_channels"] = micSelections
                    onSave()
                    isPresented = false
                    dismiss()
                }
                .disabled(!mappingCompatible)
            }
        }
        .padding()
    }
}
#endif
