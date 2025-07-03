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
    private static func createTempDir() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Earprint-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
    @State private var measurementDir: String
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

    enum Section: String, CaseIterable, Identifiable {
        case setup = "Setup"
        case execution = "Execution"
        case postProcessing = "Post-Processing"
        case roomResponse = "Room Response"
        case presets = "Presets"
        case profiles = "Profiles"
        case rooms = "Rooms"
        case visualization = "Visualization"

        var id: Self { self }
    }

    @State private var selectedSection: Section = .setup

    init() {
        _measurementDir = State(initialValue: EarprintApp.createTempDir())
    }

    var body: some Scene {
        WindowGroup {
            NavigationView {
                List(selection: $selectedSection) {
                    ForEach(Section.allCases) { section in
                        Text(section.rawValue)
                            .tag(section)
                    }
                }
                .frame(minWidth: 150)
                .listStyle(SidebarListStyle())
                detailView(for: selectedSection)
            }
            .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit EarprintGUI") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            CommandMenu("Navigate") {
                Button("Setup") { selectedSection = .setup }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Execution") { selectedSection = .execution }
                    .keyboardShortcut("2", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: Section) -> some View {
        switch section {
        case .setup:
            SetupView(viewModel: processingVM,
                      measurementDir: $measurementDir,
                      testSignal: $testSignal,
                      channelBalance: $channelBalance,
                      targetLevel: $targetLevel,
                      selectedLayout: $selectedLayout,
                      playbackDevice: $playbackDevice,
                      recordingDevice: $recordingDevice,
                      channelMapping: $channelMapping)
        case .execution:
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
        case .postProcessing:
            PostProcessingView(viewModel: processingVM,
                               measurementDir: measurementDir,
                               testSignal: testSignal,
                               playbackDevice: playbackDevice,
                               recordingDevice: recordingDevice,
                               enableCompensation: $enableCompensation,
                               headphoneEqEnabled: $headphoneEqEnabled,
                               headphoneFile: $headphoneFile,
                               compensationType: $compensationType,
                               customCompensationFile: $customCompensationFile,
                               diffuseField: $diffuseField,
                               xCurveAction: $xCurveAction,
                               xCurveType: $xCurveType,
                               xCurveInCapture: $xCurveInCapture,
                               channelBalance: $channelBalance,
                               targetLevel: $targetLevel,
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
        case .roomResponse:
            RoomResponseView(viewModel: processingVM,
                             measurementDir: measurementDir,
                             testSignal: testSignal,
                             playbackDevice: playbackDevice,
                             recordingDevice: recordingDevice)
        case .presets:
            PresetView(viewModel: processingVM,
                       measurementDir: measurementDir)
        case .profiles:
            ProfileView(viewModel: processingVM,
                        measurementDir: $measurementDir,
                        headphoneFile: $headphoneFile,
                        playbackDevice: $playbackDevice)
        case .rooms:
            RoomPresetView(viewModel: processingVM,
                           measurementDir: $measurementDir)
        case .visualization:
            VisualizationView(measurementDir: measurementDir)
        }
    }
}
#endif
