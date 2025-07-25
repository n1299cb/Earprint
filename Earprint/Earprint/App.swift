import SwiftUI

struct EarprintApp: App {
    
    // MARK: - ViewModels
    @StateObject private var processingVM = ProcessingViewModel()
    @StateObject private var configurationVM = ConfigurationViewModel()
    @StateObject private var audioDeviceVM = AudioDeviceViewModel()
    @StateObject private var recordingVM = RecordingViewModel()
    @StateObject private var workspaceManager = WorkspaceManager()
    
    // MARK: - App State
    @AppStorage("selectedSection") private var lastSectionRaw: String = Section.workspace.rawValue
    @State private var selectedSection: Section?
    @State private var showingSettings = false
    
    // MARK: - Basic App Storage for RecordingView
    @AppStorage("measurementDir") private var measurementDir: String = ""
    @AppStorage("testSignal") private var testSignal: String = ""
    
    // MARK: - sidebarView
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
            .onAppear {
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
                .environmentObject(workspaceManager)
                .frame(minWidth: 800, minHeight: 600)
            }
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
            
            CommandGroup(replacing: .appTermination) {
                Button("Quit Earprint") {
                    if configurationVM.isDirty {
                        configurationVM.saveConfiguration()
                    }
                    NSApplication.shared.terminate(nil)
                }
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
            PostProcessingView(processingVM: processingVM,
                               measurementDir: $measurementDir,
                               testSignal: $testSignal)
            .environmentObject(workspaceManager)
        case .visualization:
            VisualizationView(processingVM: processingVM)
                .environmentObject(configurationVM)
                .environmentObject(workspaceManager)
        }
    }
    
    // MARK: - Workspace Helper Functions
    
    private func initializeWorkspacePaths() {
        // Set measurement directory to current workspace if not already set
        if measurementDir.isEmpty {
            measurementDir = workspaceManager.currentWorkspace.path
        }
        
        // Set test signal to workspace test signal if available
        let workspaceTestSignal = workspaceManager.getTestSignalPath()
        if testSignal.isEmpty && !workspaceTestSignal.isEmpty {
            testSignal = workspaceTestSignal
        }
    }
    
    private func updateWorkspacePaths() {
        // Update measurement directory to current workspace
        measurementDir = workspaceManager.currentWorkspace.path
        
        // Update test signal to workspace test signal
        let workspaceTestSignal = workspaceManager.getTestSignalPath()
        if !workspaceTestSignal.isEmpty {
            testSignal = workspaceTestSignal
        }
        
        // Validate paths for recording
        recordingVM.validatePaths(measurementDir)
    }
    
    private func exportCurrentWorkspace() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Export Workspace"
        panel.prompt = "Export"
        panel.nameFieldStringValue = workspaceManager.workspaceName
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await workspaceManager.exportWorkspace(to: url)
                } catch {
                    await MainActor.run {
                        print("Export failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        #endif
    }
    
    private func clearCurrentWorkspace() {
        #if canImport(AppKit)
        let alert = NSAlert()
        alert.messageText = "Clear Workspace"
        alert.informativeText = "This will permanently delete all files in the current workspace. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: workspaceManager.currentWorkspace, includingPropertiesForKeys: nil)
                for item in contents {
                    try FileManager.default.removeItem(at: item)
                }
            } catch {
                print("Failed to clear workspace: \(error)")
            }
        }
        #endif
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
