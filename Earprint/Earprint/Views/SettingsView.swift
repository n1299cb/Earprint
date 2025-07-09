#if os(macOS)
import CoreAudio
#endif
import SwiftUI
import AppKit

struct SettingsView: View {
    // MARK: - ViewModel Dependencies - ALL RELEVANT VIEWMODELS
    @ObservedObject var configurationVM: ConfigurationViewModel
    @ObservedObject var audioDeviceVM: AudioDeviceViewModel
    @ObservedObject var processingVM: ProcessingViewModel
    @ObservedObject var recordingVM: RecordingViewModel
    @EnvironmentObject var workspaceManager: WorkspaceManager
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    @State private var selectedTab: SettingsTab = .general
    @State private var showingResetAlert = false
    @State private var showingChannelMapping = false
    
    // MARK: - Layout and Speaker Configuration
    @State private var availableLayouts: [String] = []
    @State private var selectedLayout = "7.1"
    
    // MARK: - Basic Settings (synced with ConfigurationViewModel)
    @State private var defaultMeasurementDir = ""
    @State private var defaultTestSignal = ""
    @State private var autoSaveConfiguration = true
    @State private var enableDetailedLogging = false
    @State private var rememberWindowPosition = true
    
    // MARK: - Processing Settings
    @State private var maxProcessingThreads = 0
    @State private var enableDebugMode = false
    @State private var saveIntermediateFiles = false
    
    // MARK: - Workspace Integration
    @State private var workspaceAutoCleanup = false
    @State private var maxWorkspaceSize = 1000 // MB
    
    // MARK: - Warning State
    @State private var channelWarningText: String = ""
    @State private var configurationIssues: [String] = []
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case audio = "Audio Devices"
        case processing = "Processing"
        case workspace = "Workspace"
        case advanced = "Advanced"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .audio: return "speaker.wave.3"
            case .processing: return "cpu"
            case .workspace: return "folder.badge.gearshape"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            
        } detail: {
            // Detail View
            Group {
                switch selectedTab {
                case .general:
                    generalSettingsView
                case .audio:
                    audioSettingsView
                case .processing:
                    processingSettingsView
                case .workspace:
                    workspaceSettingsView
                case .advanced:
                    advancedSettingsView
                }
            }
            .navigationTitle(selectedTab.rawValue)
            .navigationSplitViewColumnWidth(min: 500, ideal: 700)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack {
                    if !configurationIssues.isEmpty {
                        Button(action: { validateAndCleanup() }) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                        .help("Configuration issues detected")
                    }
                    
                    Button("Reset to Defaults") {
                        showingResetAlert = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .alert("Reset Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
        .sheet(isPresented: $showingChannelMapping) {
            // Integration with RecordingViewModel's speaker layouts
            if let speakerLabels = fetchSpeakerLabelsArray(layout: selectedLayout) {
                ChannelMappingView(
                    playbackChannels: audioDeviceVM.selectedOutputDevice?.maxOutputChannels ?? 0,
                    recordingChannels: audioDeviceVM.selectedInputDevice?.maxInputChannels ?? 0,
                    speakerLabels: speakerLabels,
                    playbackDevice: audioDeviceVM.selectedOutputDevice?.name ?? "",
                    channelMapping: Binding(
                        get: { self.channelMappingDictionary },
                        set: { newValue in
                            let outputChannels = newValue["output_channels"] ?? []
                            let inputChannels = newValue["input_channels"] ?? []
                            self.audioDeviceVM.setChannelMapping(input: inputChannels, output: outputChannels)
                        }
                    ),
                    isPresented: $showingChannelMapping,
                    onSave: {
                        // Channel mapping automatically saved via computed property
                    }
                )
                .frame(minWidth: 600, minHeight: 400)
            }
        }
        .onAppear {
            loadCurrentSettings()
            audioDeviceVM.refreshDevices()
            loadLayouts()
            validateConfiguration()
        }
        .onDisappear {
            saveSettings()
        }
        .onChange(of: audioDeviceVM.selectedOutputDevice) { _ in
            updateChannelWarning()
            if autoSaveConfiguration { saveSettings() }
        }
        .onChange(of: audioDeviceVM.selectedInputDevice) { _ in
            updateChannelWarning()
            if autoSaveConfiguration { saveSettings() }
        }
        .onChange(of: selectedLayout) { _ in
            updateChannelWarning()
            if autoSaveConfiguration { saveSettings() }
        }
        .onChange(of: defaultMeasurementDir) { _ in
            if autoSaveConfiguration { saveSettings() }
        }
        .onChange(of: defaultTestSignal) { _ in
            if autoSaveConfiguration { saveSettings() }
        }
        .onChange(of: workspaceManager.currentWorkspace) { _ in
            // Update measurement directory when workspace changes
            if defaultMeasurementDir.isEmpty {
                defaultMeasurementDir = workspaceManager.currentWorkspace.path
            }
        }
    }
    
    // MARK: - General Settings View
    private var generalSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Default Paths", icon: "folder") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Default Measurement Directory",
                            description: "The default location for saving measurements and recordings"
                        ) {
                            HStack {
                                Text(defaultMeasurementDir.isEmpty ?
                                     "Use current workspace" :
                                     URL(fileURLWithPath: defaultMeasurementDir).lastPathComponent)
                                    .foregroundColor(defaultMeasurementDir.isEmpty ? .secondary : .primary)
                                
                                Spacer()
                                
                                Button("Browse") {
                                    selectMeasurementDirectory()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Use Workspace") {
                                    defaultMeasurementDir = workspaceManager.currentWorkspace.path
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        SettingsRow(
                            title: "Default Test Signal",
                            description: "The default audio file used for measurements"
                        ) {
                            HStack {
                                Text(defaultTestSignal.isEmpty ?
                                     "Use workspace signal" :
                                     URL(fileURLWithPath: defaultTestSignal).lastPathComponent)
                                    .foregroundColor(defaultTestSignal.isEmpty ? .secondary : .primary)
                                
                                Spacer()
                                
                                Button("Browse") {
                                    selectTestSignal()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Use Default") {
                                    defaultTestSignal = workspaceManager.getTestSignalPath()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                SettingsSection(title: "Application Behavior", icon: "app") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Auto-save Configuration",
                            description: "Automatically save configuration changes"
                        ) {
                            Toggle("", isOn: $autoSaveConfiguration)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Show Detailed Logs",
                            description: "Display verbose logging information during processing"
                        ) {
                            Toggle("", isOn: $enableDetailedLogging)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Remember Window Position",
                            description: "Restore window size and position on app launch"
                        ) {
                            Toggle("", isOn: $rememberWindowPosition)
                                .toggleStyle(.switch)
                        }
                    }
                }
                
                // Configuration Status
                if !configurationIssues.isEmpty {
                    SettingsSection(title: "Configuration Issues", icon: "exclamationmark.triangle") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(configurationIssues, id: \.self) { issue in
                                Text("• \(issue)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            Button("Fix Issues") {
                                validateAndCleanup()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Audio Settings View
    private var audioSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Audio Devices", icon: "speaker.wave.3") {
                    VStack(spacing: 16) {
                        HStack {
                            Button("Refresh Devices") {
                                audioDeviceVM.refreshDevices()
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Text("\(audioDeviceVM.outputDevices.count) playback, \(audioDeviceVM.inputDevices.count) recording devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        SettingsRow(
                            title: "Default Playback Device",
                            description: "The audio output device used for test signal playback"
                        ) {
                            Picker("Playback Device", selection: $audioDeviceVM.selectedOutputDevice) {
                                Text("System Default").tag(Optional<AudioDevice>(nil))
                                ForEach(audioDeviceVM.outputDevices) { device in
                                    Text(audioDeviceVM.getDeviceDisplayName(device))
                                        .tag(Optional(device))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 300)
                        }
                        
                        SettingsRow(
                            title: "Default Recording Device",
                            description: "The audio input device used for capturing measurements"
                        ) {
                            Picker("Recording Device", selection: $audioDeviceVM.selectedInputDevice) {
                                Text("System Default").tag(Optional<AudioDevice>(nil))
                                ForEach(audioDeviceVM.inputDevices) { device in
                                    Text(audioDeviceVM.getDeviceDisplayName(device))
                                        .tag(Optional(device))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 300)
                        }
                    }
                }
                
                SettingsSection(title: "Speaker Layout", icon: "hifispeaker.2") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Default Speaker Layout",
                            description: "The default speaker configuration for measurements"
                        ) {
                            Picker("Layout", selection: $selectedLayout) {
                                ForEach(availableLayouts, id: \.self) { layout in
                                    Text(layout).tag(layout)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                        
                        HStack {
                            Button("Channel Mapping") {
                                showingChannelMapping = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(audioDeviceVM.selectedOutputDevice == nil || audioDeviceVM.selectedInputDevice == nil)
                            
                            Button("Auto Map Channels") {
                                audioDeviceVM.autoMapChannelsAction()
                            }
                            .buttonStyle(.bordered)
                            .disabled(audioDeviceVM.selectedOutputDevice == nil || audioDeviceVM.selectedInputDevice == nil)
                            
                            Spacer()
                            
                            if let channelMapping = audioDeviceVM.channelMapping {
                                Text("Mapped: \(channelMapping.outputChannels.count) out, \(channelMapping.inputChannels.count) in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !channelWarningText.isEmpty {
                            Text(channelWarningText)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                        
                        // Show device warnings from AudioDeviceViewModel
                        if !audioDeviceVM.deviceWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(audioDeviceVM.deviceWarnings, id: \.self) { warning in
                                    Text("⚠️ \(warning)")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Processing Settings View
    private var processingSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Performance", icon: "cpu") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Processing Threads",
                            description: "Number of threads to use for parallel processing"
                        ) {
                            Picker("Threads", selection: $maxProcessingThreads) {
                                Text("Auto").tag(0)
                                ForEach(1...ProcessInfo.processInfo.processorCount, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                
                SettingsSection(title: "Processing Status", icon: "gears") {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Current State:")
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text(processingStateDescription)
                                .foregroundColor(processingStateColor)
                        }
                        
                        if processingVM.isRunning {
                            VStack(spacing: 8) {
                                if let progress = processingVM.progress {
                                    ProgressView(value: progress)
                                        .progressViewStyle(.linear)
                                    Text("\(Int(progress * 100))% complete")
                                        .font(.caption)
                                }
                                
                                Button("Cancel Processing") {
                                    processingVM.cancel()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                        
                        SettingsRow(
                            title: "Auto-save Logs",
                            description: "Automatically save processing logs to file"
                        ) {
                            Toggle("", isOn: $processingVM.autoLog)
                                .toggleStyle(.switch)
                        }
                    }
                }
                
                SettingsSection(title: "Python Environment", icon: "terminal") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Python Executable",
                            description: "Path to the Python interpreter used for processing"
                        ) {
                            HStack {
                                Text(embeddedPythonURL != nil ? "Using embedded Python" : "Using system Python")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if embeddedPythonURL == nil {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                        .help("Embedded Python not found - using system Python")
                                }
                            }
                        }
                        
                        SettingsRow(
                            title: "Scripts Directory",
                            description: "Location of the Python processing scripts"
                        ) {
                            HStack {
                                Text("Using bundled scripts")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Open Scripts") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: scriptsRoot.path)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Workspace Settings View
    private var workspaceSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Current Workspace", icon: "folder.badge.gearshape") {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Active Workspace:")
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text(workspaceManager.workspaceName)
                                .foregroundColor(.secondary)
                        }
                        
                        let stats = workspaceManager.getWorkspaceStats()
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Files: \(stats.fileCount)")
                                Text("Size: \(stats.formattedSize)")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("Audio: \(stats.audioFiles)")
                                Text("CSV: \(stats.csvFiles)")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Button("Open Workspace") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspaceManager.currentWorkspace.path)
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Switch Workspace") {
                                // This would trigger workspace selection
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                        }
                    }
                }
                
                SettingsSection(title: "Test Signals", icon: "waveform") {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Available Signals:")
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(workspaceManager.availableTestSignals.count) bundled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let defaultSignal = workspaceManager.availableTestSignals.first(where: { $0.isDefault }) {
                            HStack {
                                Text("Default:")
                                Text(defaultSignal.name)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .font(.caption)
                        }
                        
                        Button("Refresh Test Signals") {
                            workspaceManager.loadAvailableTestSignals()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                SettingsSection(title: "Workspace Management", icon: "gear") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Auto-cleanup Old Files",
                            description: "Automatically remove old temporary files"
                        ) {
                            Toggle("", isOn: $workspaceAutoCleanup)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Max Workspace Size (MB)",
                            description: "Maximum size before cleanup warning"
                        ) {
                            TextField("Size", value: $maxWorkspaceSize, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Advanced Settings View
    private var advancedSettingsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Debugging", icon: "ladybug") {
                    VStack(spacing: 16) {
                        SettingsRow(
                            title: "Enable Debug Mode",
                            description: "Enable verbose logging and debug output"
                        ) {
                            Toggle("", isOn: $enableDebugMode)
                                .toggleStyle(.switch)
                        }
                        
                        SettingsRow(
                            title: "Save Intermediate Files",
                            description: "Keep intermediate processing files for debugging"
                        ) {
                            Toggle("", isOn: $saveIntermediateFiles)
                                .toggleStyle(.switch)
                        }
                        
                        if enableDebugMode {
                            VStack(spacing: 8) {
                                HStack {
                                    Button("Export Debug Info") {
                                        exportDebugInformation()
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("Clear Log") {
                                        processingVM.clearLog()
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                
                SettingsSection(title: "Configuration Management", icon: "doc.badge.gearshape") {
                    VStack(spacing: 16) {
                        HStack {
                            Button("Export Configuration") {
                                exportConfiguration()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Import Configuration") {
                                importConfiguration()
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                        }
                        
                        HStack {
                            Button("Validate Configuration") {
                                validateConfiguration()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Cleanup Configuration") {
                                configurationVM.cleanupConfiguration()
                                validateConfiguration()
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                        }
                        
                        if configurationVM.isDirty {
                            Text("⚠️ Configuration has unsaved changes")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Computed Properties
    private var channelMappingDictionary: [String: [Int]] {
        guard let mapping = audioDeviceVM.channelMapping else {
            return [:]
        }
        return [
            "output_channels": mapping.outputChannels,
            "input_channels": mapping.inputChannels
        ]
    }
    
    private var processingStateDescription: String {
        switch processingVM.state {
        case .idle: return "Idle"
        case .running: return "Processing..."
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
    
    private var processingStateColor: Color {
        switch processingVM.state {
        case .idle: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    // MARK: - Helper Methods
    private func selectMeasurementDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            defaultMeasurementDir = url.path
        }
    }
    
    private func selectTestSignal() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        
        if panel.runModal() == .OK, let url = panel.url {
            defaultTestSignal = url.path
        }
    }
    
    // MARK: - Configuration Integration
    private func loadCurrentSettings() {
        // Load settings from ConfigurationViewModel
        defaultMeasurementDir = configurationVM.appConfiguration.defaultMeasurementDir
        defaultTestSignal = configurationVM.appConfiguration.defaultTestSignal
        autoSaveConfiguration = configurationVM.appConfiguration.autoSaveResults
        
        // Load from other ViewModels
        enableDetailedLogging = processingVM.autoLog
        
        // Set defaults if empty
        if defaultMeasurementDir.isEmpty {
            defaultMeasurementDir = workspaceManager.currentWorkspace.path
        }
        if defaultTestSignal.isEmpty {
            defaultTestSignal = workspaceManager.getTestSignalPath()
        }
    }
    
    private func saveSettings() {
        // Save to ConfigurationViewModel
        configurationVM.updateDefaultMeasurementDir(defaultMeasurementDir)
        configurationVM.updateDefaultTestSignal(defaultTestSignal)
        configurationVM.updateAutoSaveResults(autoSaveConfiguration)
        
        // Save to other ViewModels
        processingVM.autoLog = enableDetailedLogging
        
        // Trigger save if dirty
        if configurationVM.isDirty {
            configurationVM.saveConfiguration()
        }
    }
    
    private func validateConfiguration() {
        configurationIssues = configurationVM.validateConfiguration()
        configurationIssues += audioDeviceVM.validateDeviceConfiguration()
    }
    
    private func validateAndCleanup() {
        configurationVM.cleanupConfiguration()
        validateConfiguration()
    }
    
    private func resetToDefaults() {
        // Reset all ViewModels
        configurationVM.resetToDefaults()
        audioDeviceVM.selectedInputDevice = nil
        audioDeviceVM.selectedOutputDevice = nil
        audioDeviceVM.refreshDevices()
        
        // Reset local state
        selectedLayout = "7.1"
        channelWarningText = ""
        configurationIssues = []
        enableDebugMode = false
        saveIntermediateFiles = false
        workspaceAutoCleanup = false
        maxWorkspaceSize = 1000
        
        // Reload settings
        loadCurrentSettings()
    }
    
    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "earprint-config.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                try await configurationVM.exportConfiguration(to: url)
            }
        }
    }
    
    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                try await configurationVM.importConfiguration(from: url)
                loadCurrentSettings()
                validateConfiguration()
            }
        }
    }
    
    private func exportDebugInformation() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "earprint-debug-info"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Export debug information including logs, configuration, etc.
            let debugInfo = createDebugReport()
            try? debugInfo.write(to: url.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        }
    }
    
    private func createDebugReport() -> String {
        var report = "Earprint Debug Report\n"
        report += "Generated: \(Date())\n\n"
        
        // System Info
        report += "System Information:\n"
        report += "- macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        report += "- Processor Count: \(ProcessInfo.processInfo.processorCount)\n\n"
        
        // Audio Devices
        report += "Audio Devices:\n"
        report += "- Output Devices: \(audioDeviceVM.outputDevices.count)\n"
        report += "- Input Devices: \(audioDeviceVM.inputDevices.count)\n"
        if let output = audioDeviceVM.selectedOutputDevice {
            report += "- Selected Output: \(output.name) (\(output.maxOutputChannels) channels)\n"
        }
        if let input = audioDeviceVM.selectedInputDevice {
            report += "- Selected Input: \(input.name) (\(input.maxInputChannels) channels)\n"
        }
        report += "\n"
        
        // Configuration Issues
        if !configurationIssues.isEmpty {
            report += "Configuration Issues:\n"
            for issue in configurationIssues {
                report += "- \(issue)\n"
            }
            report += "\n"
        }
        
        // Processing Log
        if !processingVM.log.isEmpty {
            report += "Processing Log:\n"
            report += processingVM.log
        }
        
        return report
    }
    
    // MARK: - Speaker Layout Methods (integrated with RecordingViewModel)
    private func loadLayouts() {
        recordingVM.getSpeakerLayouts { layouts in
            self.availableLayouts = Array(layouts.keys).sorted()
            if self.selectedLayout.isEmpty, let first = self.availableLayouts.first {
                self.selectedLayout = first
            }
        }
    }
    
    private func fetchSpeakerLabels(layout: String) -> [String] {
        // Use the same approach as in SettingsView but leverage RecordingViewModel
        guard let scriptsRoot = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
            return fallbackSpeakerLabels(for: layout)
        }
        
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        
        if let embeddedPythonURL = Bundle.main.resourceURL?.appendingPathComponent("EmbeddedPython/Python.framework/Versions/3.9/bin/python3"),
           FileManager.default.fileExists(atPath: embeddedPythonURL.path) {
            // Use embedded Python
            process.executableURL = embeddedPythonURL
            process.arguments = [
                "-c",
                "import json,constants,sys; print(json.dumps([c for g in constants.SPEAKER_LAYOUTS.get('" + layout + "', []) for c in g]))"
            ]
            process.environment = [
                "PYTHONHOME": embeddedPythonURL.deletingLastPathComponent().deletingLastPathComponent().path,
                "PYTHONPATH": scriptsRoot.path
            ]
        } else {
            // Fallback to system Python
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                "-c",
                "import json,constants,sys; print(json.dumps([c for g in constants.SPEAKER_LAYOUTS.get('" + layout + "', []) for c in g]))"
            ]
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return arr
            }
        } catch {
            print("⚠️ Failed to execute Python for speaker labels: \(error)")
        }
        
        return fallbackSpeakerLabels(for: layout)
    }
    
    private func fallbackSpeakerLabels(for layout: String) -> [String] {
        switch layout {
        case "5.1":
            return ["FL", "FR", "C", "LFE", "SL", "SR"]
        case "7.1":
            return ["FL", "FR", "C", "LFE", "SL", "SR", "BL", "BR"]
        case "9.1.6":
            return ["FL", "FR", "C", "LFE", "SL", "SR", "BL", "BR", "TFL", "TFR", "TML", "TMR", "TBL", "TBR", "TC", "BC"]
        case "2.0", "Stereo":
            return ["FL", "FR"]
        case "1.0", "Mono":
            return ["C"]
        default:
            return []
        }
    }
    
    private func fetchSpeakerLabelsArray(layout: String) -> [String]? {
        let labels = fetchSpeakerLabels(layout: layout)
        return labels.isEmpty ? nil : labels
    }
    
    private func updateChannelWarning() {
        guard let outputDevice = audioDeviceVM.selectedOutputDevice,
              let inputDevice = audioDeviceVM.selectedInputDevice else {
            channelWarningText = ""
            return
        }
        
        var warnings: [String] = []
        let speakerCount = fetchSpeakerLabels(layout: selectedLayout).count
        
        if outputDevice.maxOutputChannels < speakerCount && speakerCount > 0 {
            warnings.append("Playback device only has \(outputDevice.maxOutputChannels) channels while layout requires \(speakerCount)")
        }
        if inputDevice.maxInputChannels < 2 {
            let suffix = inputDevice.maxInputChannels == 1 ? "" : "s"
            warnings.append("Recording device only has \(inputDevice.maxInputChannels) channel\(suffix); two are required")
        }
        
        channelWarningText = warnings.joined(separator: ". ")
    }
}

// MARK: - Supporting Views
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content
    
    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.headline)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            content()
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let description: String
    let content: () -> Content
    
    init(title: String, description: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            content()
        }
        .padding(.vertical, 4)
    }
}

