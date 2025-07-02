#if canImport(SwiftUI)
import SwiftUI

struct ChannelMappingView: View {
    var playbackChannels: Int
    var recordingChannels: Int
    var speakerLabels: [String]
    @Binding var channelMapping: [String: [Int]]
    var onSave: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var speakerSelections: [Int]
    @State private var micSelections: [Int]

    init(playbackChannels: Int, recordingChannels: Int, speakerLabels: [String], channelMapping: Binding<[String: [Int]]>, onSave: @escaping () -> Void = {}) {
        self.playbackChannels = playbackChannels
        self.recordingChannels = recordingChannels
        self.speakerLabels = speakerLabels
        self._channelMapping = channelMapping
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
                ForEach(speakerLabels.indices, id: \.self) { idx in
                    Picker(speakerLabels[idx], selection: $speakerSelections[idx]) {
                        ForEach(0..<playbackChannels, id: \.self) { ch in
                            Text("\(ch + 1)").tag(ch)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
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

    var body: some View {
        VStack {
            HStack {
                speakerSection
                microphoneSection
            }
            Button("Save") {
                channelMapping["output_channels"] = speakerSelections
                channelMapping["input_channels"] = micSelections
                onSave()
                dismiss()
            }
        }
        .padding()
    }
}
#endif