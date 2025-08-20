import SwiftUI

struct EarprintApp: App {
    
    // MARK: - ViewModels
    @StateObject private var processingVM = ProcessingViewModel()
    @StateObject private var configurationVM = ConfigurationViewModel()
    @StateObject private var audioDeviceVM = AudioDeviceViewModel()
    @StateObject private var recordingVM = RecordingViewModel()
    @StateObject private var workspaceManager = WorkspaceManager()
    @StateObject private var guideManager = GuideManager()
    
    // MARK: - App State
    @AppStorage("selectedSection") private var lastSectionRaw: String = Section.workspace.rawValue
    @AppStorage("hasCompletedFirstRun") private var hasCompletedFirstRun: Bool = false
    @State private var selectedSection: Section?
    @State private var showingSettings = false
    @State private var showingFirstRun = false
    
    // MARK: - Basic App Storage for RecordingView
    @AppStorage("measurementDir") private var measurementDir: String = ""
    @AppStorage("testSignal") private var testSignal: String = ""
    
    // MARK: - Views
    private var sidebarView: some View {
        List(Section.allCases, id: \.self, selection: $selectedSection) { section in
            NavigationLink(value: section) {
                Label(section.rawValue, systemImage: section.icon)
            }
        }
        .navigationTitle("Earprint")
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
    }
    
    private var detailView: some View {
        Group {
            if let section = selectedSection {
                detailView(for: section)
            } else {
                Text("Select a section from the sidebar to get started")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
        }
        .navigationSplitViewColumnWidth(min: 500, ideal: 800)
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                sidebarView
            } detail: {
                detailView
            }
            
            .environmentObject(guideManager)
            .withGuide(guideManager)
            
            .onAppear {
                // Check for first run
                if !hasCompletedFirstRun {
                    showingFirstRun = true
                }
                
                // Set initial section if none selected
                if selectedSection == nil {
                    selectedSection = Section(rawValue: lastSectionRaw) ?? .workspace
                }
                
                // Load configuration when app starts
                configurationVM.loadConfiguration()
                audioDeviceVM.refreshDevices()
                
                // Initialize workspace paths with current workspace
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
                
                // ADD THIS LINE:
                guideManager.loadCompletedSteps()
            }
            .onChange(of: selectedSection) { newValue in
                lastSectionRaw = newValue?.rawValue ?? Section.workspace.rawValue
            }
            .onChange(of: measurementDir) { newValue in
                recordingVM.validatePaths(newValue)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    configurationVM: configurationVM,
                    audioDeviceVM: audioDeviceVM,
                    processingVM: processingVM,
                    recordingVM: recordingVM
                )
                .environmentObject(configurationVM)
                .environmentObject(workspaceManager)
                .frame(minWidth: 800, minHeight: 600)
            }
            .sheet(isPresented: $showingFirstRun) {
                FirstRunExperienceView {
                    hasCompletedFirstRun = true
                    showingFirstRun = false
                    selectedSection = .workspace
                    guideManager.saveCompletedSteps()
                    
                    // Start guide here in App.swift where guideManager is available
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        guideManager.startGuide(.firstRun)
                    }
                }
                .environmentObject(workspaceManager)
                .environmentObject(configurationVM)
            }
            .environmentObject(guideManager)
            .withGuide(guideManager)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandGroup(after: .appSettings) {
                Button("Tutorial...") {
                    showingFirstRun = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .help) {
                Divider()
                
                Button("Setup Guide") {
                    guideManager.startGuide(.firstRun)
                }
                .keyboardShortcut("?", modifiers: [.command, .shift])
                
                Button("Recording Guide") {
                    guideManager.startGuide(.recording)
                }
                
                Button("Processing Guide") {
                    guideManager.startGuide(.processing)
                }
                
                Button("Workspace Guide") {
                    guideManager.startGuide(.workspace)
                }
                
                if guideManager.isActive {
                    Divider()
                    Button("End Current Guide") {
                        guideManager.endGuide()
                    }
                    .keyboardShortcut(.escape)
                }
            }
            
            CommandGroup(replacing: .appTermination) {
                Button("Quit Earprint") {
                    if configurationVM.isDirty {
                        configurationVM.saveConfiguration()
                    }
                    guideManager.saveCompletedSteps()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("Q", modifiers: .command)
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
            .environmentObject(workspaceManager)
        case .workspace:
            WorkspaceView()
                .environmentObject(workspaceManager)
        case .postProcessing:
            PostProcessingView(
                processingVM: processingVM,
                measurementDir: $measurementDir,
                testSignal: $testSignal
            )
            .environmentObject(workspaceManager)
        case .visualization:
            FrequencyVisualizationView(measurementDir: $measurementDir)
                .environmentObject(configurationVM)
                .environmentObject(workspaceManager)
        }
    }
}

// MARK: - Section Enum
enum Section: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case recording = "Recording"
    case postProcessing = "Post-Processing"
    case visualization = "Visualization"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .recording: return "record.circle"
        case .workspace: return "folder.badge.gearshape"
        case .postProcessing: return "wrench"
        case .visualization: return "chart.line.uptrend.xyaxis"
        }
    }
}
