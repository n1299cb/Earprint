import SwiftUI

struct EarprintApp: App {
    
    // MARK: - ViewModels
    @StateObject private var processingVM = ProcessingViewModel()
    @StateObject private var configurationVM = ConfigurationViewModel()
    @StateObject private var audioDeviceVM = AudioDeviceViewModel()
    @StateObject private var recordingVM = RecordingViewModel()
    
    // MARK: - App State
    @AppStorage("selectedSection") private var lastSectionRaw: String = Section.recording.rawValue
    @State private var selectedSection: Section?
    @State private var showingSettings = false
    
    // MARK: - Basic App Storage for RecordingView
    @AppStorage("measurementDir") private var measurementDir: String = ""
    @AppStorage("testSignal") private var testSignal: String = ""
    
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                // Sidebar
                List(Section.allCases, id: \.self, selection: $selectedSection) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.icon)
                    }
                }
                .navigationTitle("Earprint")
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                .onAppear {
                    print("Sidebar appeared with sections: \(Section.allCases.map { $0.rawValue })")
                    print("Selected section: \(selectedSection?.rawValue ?? "nil")")
                    func testResources() {
                        if let scriptsPath = Bundle.main.resourcePath {
                            let scriptsURL = URL(fileURLWithPath: scriptsPath).appendingPathComponent("Scripts")
                            print("Scripts path: \(scriptsURL.path)")
                            print("Scripts exists: \(FileManager.default.fileExists(atPath: scriptsURL.path))")
                            
                            // List contents
                            if let contents = try? FileManager.default.contentsOfDirectory(atPath: scriptsURL.path) {
                                print("Scripts contents: \(contents)")
                            }
                        }
                    }
                }
            } detail: {
                // Detail View
                Group {
                    if let section = selectedSection {
                        detailView(for: section)
                    } else {
                        WelcomeView()
                    }
                }
                .navigationSplitViewColumnWidth(min: 500, ideal: 800)
            }
            .onAppear {
                // Set initial section if none selected
                if selectedSection == nil {
                    selectedSection = Section(rawValue: lastSectionRaw) ?? .recording
                }
                
                // Load configuration when app starts
                configurationVM.loadConfiguration()
                audioDeviceVM.refreshDevices()
                
                // Load defaults from configuration and initialize RecordingViewModel
                if measurementDir.isEmpty && !configurationVM.appConfiguration.defaultMeasurementDir.isEmpty {
                    measurementDir = configurationVM.appConfiguration.defaultMeasurementDir
                }
                if testSignal.isEmpty && !configurationVM.appConfiguration.defaultTestSignal.isEmpty {
                    testSignal = configurationVM.appConfiguration.defaultTestSignal
                }
                
                // Initialize recording validation
                if !measurementDir.isEmpty {
                    recordingVM.validatePaths(measurementDir)
                }
            }
            .onChange(of: selectedSection) { newValue in
                lastSectionRaw = newValue?.rawValue ?? Section.recording.rawValue
            }
            .onChange(of: measurementDir) { newValue in
                // Update recording validation when measurement directory changes
                recordingVM.validatePaths(newValue)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    configurationVM: configurationVM,
                    audioDeviceVM: audioDeviceVM
                )
                .frame(minWidth: 800, minHeight: 600)
            }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Earprint") {
                    // Save configuration before quitting
                    if configurationVM.isDirty {
                        configurationVM.saveConfiguration()
                    }
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            
            CommandGroup(after: .appInfo) {
                Divider()
                
                Button("Preferences...") {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("Navigate") {
                Button("Recording") {
                    selectedSection = .recording
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Visualization") {
                    selectedSection = .visualization
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Divider()
                
                Button("Preferences...") {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("Audio") {
                Button("Refresh Audio Devices") {
                    audioDeviceVM.refreshDevices()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Button("Auto Map Channels") {
                    audioDeviceVM.autoMapChannelsAction()
                }
                .disabled(audioDeviceVM.selectedInputDevice == nil || audioDeviceVM.selectedOutputDevice == nil)
            }
            
            CommandMenu("Recording") {
                Button("Start Recording") {
                    // This would trigger recording from menu
                }
                .disabled(processingVM.isRunning)
                .keyboardShortcut("r", modifiers: .command)
                
                Button("Stop Recording") {
                    processingVM.cancel()
                }
                .disabled(!processingVM.isRunning)
                .keyboardShortcut(".", modifiers: .command)
                
                Divider()
                
                Button("Open Recording Directory") {
                    if !measurementDir.isEmpty {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: measurementDir)
                    }
                }
                .disabled(measurementDir.isEmpty)
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: Section) -> some View {
        switch section {
        case .recording:
            RecordingView(
                processingVM: processingVM,
                recordingVM: recordingVM,
                audioDeviceVM: audioDeviceVM,
                configurationVM: configurationVM
            )
        case .visualization:
            VisualizationView(processingVM: processingVM)
                .environmentObject(configurationVM)
        }
    }
}

// MARK: - Welcome View
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Welcome to Earprint")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Create personalized binaural room impulse responses for immersive headphone audio")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Select Recording from the sidebar to start")
                Text("• Configure audio devices in Settings")
                Text("• View results in Visualization")
                Text("• Use keyboard shortcuts for quick navigation")
            }
            .font(.body)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: 600)
        .padding()
    }
}

// MARK: - Section Enum
enum Section: String, CaseIterable, Identifiable {
    case recording = "Recording"
    case visualization = "Visualization"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .recording: return "record.circle"
        case .visualization: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Placeholder Views for missing implementations
struct VisualizationView: View {
    @ObservedObject var processingVM: ProcessingViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Visualization")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("View frequency response graphs and analysis")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Frequency response charts")
                Text("• Before/after comparisons")
                Text("• Processing results analysis")
                Text("• Export graphs and data")
            }
            .font(.body)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: 600)
        .padding()
        .navigationTitle("Visualization")
    }
}
