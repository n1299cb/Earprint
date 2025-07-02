#if canImport(SwiftUI)
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct EarprintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var measurementDir: String = ""
    @State private var testSignal: String = ""
    @State private var channelBalance: String = ""
    @State private var targetLevel: String = ""
    @State private var selectedLayout: String = "7.1"
    @State private var playbackDevice: String = ""
    @State private var recordingDevice: String = ""
    @State private var channelMapping: [String: [Int]] = [:]
    @State private var enableCompensation: Bool = false
    @State private var headphoneEqEnabled: Bool = false
    @State private var headphoneFile: String = ""
    @State private var compensationType: String = "diffuse"
    @State private var customCompensationFile: String = ""
    @State private var diffuseField: Bool = false
    @State private var xCurveAction: String = "None"
    @State private var xCurveType: String = "minus3db_oct"
    @State private var xCurveInCapture: Bool = false
    @State private var decayTime: String = ""
    @State private var decayEnabled: Bool = false
    @State private var specificLimit: String = ""
    @State private var specificLimitEnabled: Bool = false
    @State private var genericLimit: String = ""
    @State private var genericLimitEnabled: Bool = false
    @State private var frCombinationMethod: String = "average"
    @State private var frCombinationEnabled: Bool = false
    @State private var roomCorrection: Bool = false
    @State private var roomTarget: String = ""
    @State private var micCalibration: String = ""
    @State private var interactiveDelays: Bool = false
    @StateObject private var processingVM = ProcessingViewModel()
    @State private var selectedTab: Int = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                SetupView(viewModel: processingVM,
                          measurementDir: $measurementDir,
                          testSignal: $testSignal,
                          channelBalance: $channelBalance,
                          targetLevel: $targetLevel,
                          selectedLayout: $selectedLayout,
                          playbackDevice: $playbackDevice,
                          recordingDevice: $recordingDevice,
                          channelMapping: $channelMapping)
                    .tabItem { Text("Setup") }
                    .tag(0)
                ExecutionView(viewModel: processingVM,
                              measurementDir: measurementDir,
                              testSignal: testSignal,
                              channelBalance: channelBalance,
                              targetLevel: targetLevel,
                              playbackDevice: playbackDevice,
                              recordingDevice: recordingDevice,
                              outputChannels: channelMapping["output_channels"] ?? [],
                              inputChannels: channelMapping["input_channels"] ?? [],
                              selectedLayout: selectedLayout,
                              enableCompensation: $enableCompensation,
                              headphoneEqEnabled: $headphoneEqEnabled,
                              headphoneFile: $headphoneFile,
                              compensationType: $compensationType,
                              customCompensationFile: $customCompensationFile,
                              diffuseField: $diffuseField,
                              xCurveAction: $xCurveAction,
                              xCurveType: $xCurveType,
                              xCurveInCapture: $xCurveInCapture,
                              decayTime: decayTime,
                              decayEnabled: decayEnabled,
                              specificLimit: specificLimit,
                              specificLimitEnabled: specificLimitEnabled,
                              genericLimit: genericLimit,
                              genericLimitEnabled: genericLimitEnabled,
                              frCombinationMethod: frCombinationMethod,
                              frCombinationEnabled: frCombinationEnabled,
                              roomCorrection: roomCorrection,
                              roomTarget: roomTarget,
                              micCalibration: micCalibration,
                              interactiveDelays: interactiveDelays)
                    .tabItem { Text("Execution") }
                    .tag(1)
                HeadphoneEQView(viewModel: processingVM,
                                measurementDir: measurementDir,
                                testSignal: testSignal,
                                playbackDevice: playbackDevice,
                                recordingDevice: recordingDevice)
                    .tabItem { Text("Headphone EQ") }
                    .tag(2)
                RoomResponseView(viewModel: processingVM,
                                 measurementDir: measurementDir,
                                 testSignal: testSignal,
                                 playbackDevice: playbackDevice,
                                 recordingDevice: recordingDevice)
                    .tabItem { Text("Room Response") }
                    .tag(3)
                ProcessingOptionsView(channelBalance: $channelBalance,
                                     targetLevel: $targetLevel,
                                     testSignal: $testSignal,
                                     decayTime: $decayTime,
                                     decayEnabled: $decayEnabled,
                                     specificLimit: $specificLimit,
                                     specificLimitEnabled: $specificLimitEnabled,
                                     genericLimit: $genericLimit,
                                     genericLimitEnabled: $genericLimitEnabled,
                                     frCombinationMethod: $frCombinationMethod,
                                     frCombinationEnabled: $frCombinationEnabled,
                                     roomCorrection: $roomCorrection,
                                     roomTarget: $roomTarget,
                                     micCalibration: $micCalibration,
                                     interactiveDelays: $interactiveDelays)
                    .tabItem { Text("Processing Options") }
                    .tag(4)
                CompensationView(viewModel: processingVM,
                                 enableCompensation: $enableCompensation,
                                 headphoneEqEnabled: $headphoneEqEnabled,
                                 headphoneFile: $headphoneFile,
                                 compensationType: $compensationType,
                                 customCompensationFile: $customCompensationFile,
                                 diffuseField: $diffuseField,
                                 xCurveAction: $xCurveAction,
                                 xCurveType: $xCurveType,
                                 xCurveInCapture: $xCurveInCapture,
                                 measurementDir: measurementDir,
                                 testSignal: testSignal,
                                 playbackDevice: playbackDevice,
                                 recordingDevice: recordingDevice)
                    .tabItem { Text("Compensation") }
                    .tag(5)
                PresetView(viewModel: processingVM,
                           measurementDir: measurementDir)
                    .tabItem { Text("Presets") }
                    .tag(6)
                ProfileView(viewModel: processingVM,
                            measurementDir: $measurementDir,
                            headphoneFile: $headphoneFile,
                            playbackDevice: $playbackDevice)
                    .tabItem { Text("Profiles") }
                    .tag(7)
                RoomPresetView(viewModel: processingVM,
                               measurementDir: $measurementDir)
                    .tabItem { Text("Rooms") }
                    .tag(8)
                VisualizationView(measurementDir: measurementDir)
                    .tabItem { Text("Visualization") }
                    .tag(9)
            }
            .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit EarprintGUI") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            CommandMenu("Navigate") {
                Button("Setup") { selectedTab = 0 }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Execution") { selectedTab = 1 }
                    .keyboardShortcut("2", modifiers: .command)
            }
        }
    }
}
#endif