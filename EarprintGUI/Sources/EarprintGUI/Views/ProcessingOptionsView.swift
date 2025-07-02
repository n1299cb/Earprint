#if canImport(SwiftUI)
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif

struct ProcessingOptionsView: View {
    @Binding var channelBalance: String
    @Binding var targetLevel: String
    @Binding var testSignal: String
    @Binding var decayTime: String
    @Binding var decayEnabled: Bool
    @Binding var specificLimit: String
    @Binding var specificLimitEnabled: Bool
    @Binding var genericLimit: String
    @Binding var genericLimitEnabled: Bool
    @Binding var frCombinationMethod: String
    @Binding var frCombinationEnabled: Bool
    @Binding var roomCorrection: Bool
    @Binding var roomTarget: String
    @Binding var micCalibration: String
    @Binding var interactiveDelays: Bool

#if canImport(AVFoundation)
    @StateObject private var previewer = AudioPreviewer()
    @State private var isPreviewing = false
#endif

    var body: some View {
        Form {
            Picker("Channel Balance", selection: $channelBalance) {
                Text("Off").tag("off")
                Text("Left").tag("left")
                Text("Right").tag("right")
                Text("Average").tag("avg")
                Text("Minimum").tag("min")
                Text("Mids").tag("mids")
                Text("Trend").tag("trend")
            }
            TextField("Target Level", text: $targetLevel)
            Toggle("Decay Time", isOn: $decayEnabled)
            if decayEnabled {
                TextField("Seconds", text: $decayTime)
            }
            Toggle("Interactive Delays", isOn: $interactiveDelays)
            Toggle("Enable Room Correction", isOn: $roomCorrection)
            if roomCorrection {
                HStack {
                    TextField("Room Target File", text: $roomTarget)
                    Button("Browse") {
                        if let path = openPanel(directory: false, startPath: roomTarget) { roomTarget = path }
                    }
                }
                HStack {
                    TextField("Mic Calibration File", text: $micCalibration)
                    Button("Browse") {
                        if let path = openPanel(directory: false, startPath: micCalibration) { micCalibration = path }
                    }
                }
                Toggle("Specific Limit", isOn: $specificLimitEnabled)
                if specificLimitEnabled {
                    TextField("Hz", text: $specificLimit)
                }
                Toggle("Generic Limit", isOn: $genericLimitEnabled)
                if genericLimitEnabled {
                    TextField("Hz", text: $genericLimit)
                }
                Toggle("FR Combination", isOn: $frCombinationEnabled)
                if frCombinationEnabled {
                    Picker("Method", selection: $frCombinationMethod) {
                        Text("average").tag("average")
                        Text("conservative").tag("conservative")
                    }
                }
            }
#if canImport(AVFoundation)
            Button(isPreviewing ? "Stop Preview" : "Start Preview") {
                if isPreviewing {
                    previewer.stop()
                } else if !testSignal.isEmpty {
                    previewer.start(url: URL(fileURLWithPath: testSignal), balance: channelBalance)
                }
                isPreviewing.toggle()
            }
            .disabled(testSignal.isEmpty)
#endif
        }
        .padding()
    }

    // openPanel helper is provided by Utilities.swift
}
#endif