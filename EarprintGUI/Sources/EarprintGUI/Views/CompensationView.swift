#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct CompensationView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    @Binding var enableCompensation: Bool
    @Binding var headphoneEqEnabled: Bool
    @Binding var headphoneFile: String
    @Binding var compensationType: String
    @Binding var customCompensationFile: String
    @Binding var diffuseField: Bool
    @Binding var xCurveAction: String
    @Binding var xCurveType: String
    @Binding var xCurveInCapture: Bool
    var measurementDir: String = ""
    var testSignal: String = ""
    var playbackDevice: String = ""
    var recordingDevice: String = ""

    private let compensationTypes = ["diffuse", "free", "custom"]
    private let xCurveActions = ["None", "Apply X-Curve", "Remove X-Curve"]
    private let xCurveTypes = ["minus3db_oct", "minus1p5db_oct"]

    var body: some View {
        Form {
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
            Button("Record Headphone EQ") {
                viewModel.recordHeadphoneEQ(
                    measurementDir: measurementDir,
                    testSignal: testSignal,
                    playbackDevice: playbackDevice,
                    recordingDevice: recordingDevice
                )
            }
        }
        .padding()
    }

    // openPanel helper is provided by Utilities.swift
}
#endif
