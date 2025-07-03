#if canImport(SwiftUI)
import SwiftUI
import AppKit

/// Combined view that merges Headphone EQ recording,
/// compensation options, and general processing controls.
struct PostProcessingView: View {
    @ObservedObject var viewModel: ProcessingViewModel

    // Headphone EQ parameters
    var measurementDir: String
    var testSignal: String
    var playbackDevice: String
    var recordingDevice: String

    // Compensation bindings
    @Binding var enableCompensation: Bool
    @Binding var headphoneEqEnabled: Bool
    @Binding var headphoneFile: String
    @Binding var compensationType: String
    @Binding var customCompensationFile: String
    @Binding var diffuseField: Bool
    @Binding var xCurveAction: String
    @Binding var xCurveType: String
    @Binding var xCurveInCapture: Bool

    // Processing option bindings
    @Binding var channelBalance: String
    @Binding var targetLevel: String
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

    @State private var showHeadphone = true
    @State private var showComp = true
    @State private var showOptions = true

    private let xCurveActions = ["None", "Apply X-Curve", "Remove X-Curve"]
    private let xCurveTypes = ["minus3db_oct", "minus1p5db_oct"]

    var body: some View {
        Form {
            DisclosureGroup("Headphone EQ", isExpanded: $showHeadphone) {
                Text("Record the frequency response of your headphones using binaural microphones.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Record Headphone EQ") {
                    viewModel.recordHeadphoneEQ(measurementDir: measurementDir,
                                                testSignal: testSignal,
                                                playbackDevice: playbackDevice,
                                                recordingDevice: recordingDevice)
                }
                .disabled(measurementDir.isEmpty || testSignal.isEmpty)
                if viewModel.isRunning {
                    if let progress = viewModel.progress {
                        ProgressView(value: progress)
                            .frame(maxWidth: .infinity)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    Button("Clear Log") { viewModel.clearLog() }
                        .disabled(viewModel.log.isEmpty)
                    Button("Save Log") {
                        if let url = savePanel(startPath: measurementDir) {
                            try? viewModel.log.write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                    .disabled(viewModel.log.isEmpty)
                }
                ScrollView {
                    Text(viewModel.log)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            DisclosureGroup("Compensation Options", isExpanded: $showComp) {
                Toggle("Enable Compensation", isOn: $enableCompensation)
                Toggle("Enable Headphone EQ", isOn: $headphoneEqEnabled)
                HStack {
                    TextField("Headphone EQ File", text: $headphoneFile)
                    Button("Browse") {
                        if let path = openPanel(directory: false, startPath: headphoneFile) { headphoneFile = path }
                    }
                }
                Picker("Compensation Type", selection: $compensationType) {
                    Text("Diffuse-field").tag("diffuse")
                    Text("Free-field").tag("free")
                    Text("Custom").tag("custom")
                }
                if compensationType == "custom" {
                    HStack {
                        TextField("Custom Compensation File", text: $customCompensationFile)
                        Button("Browse") {
                            if let path = openPanel(directory: false, startPath: customCompensationFile) { customCompensationFile = path }
                        }
                    }
                }
                Toggle("Apply Diffuse-Field Compensation", isOn: $diffuseField)
                Picker("X-Curve Action", selection: $xCurveAction) {
                    ForEach(xCurveActions, id: \.self) { Text($0) }
                }
                Picker("X-Curve Type", selection: $xCurveType) {
                    ForEach(xCurveTypes, id: \.self) { Text($0) }
                }
                Toggle("Capture Includes X-Curve", isOn: $xCurveInCapture)
            }

            DisclosureGroup("Processing Options", isExpanded: $showOptions) {
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
                }
            }
            .padding()
        }

    /// Present a save panel pre-populated with ``startPath``.
    func savePanel(startPath: String) -> URL? {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.directoryURL = URL(fileURLWithPath: startPath)
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return nil
        #endif
    }
}
#endif