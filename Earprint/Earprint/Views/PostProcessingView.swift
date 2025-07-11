#if canImport(SwiftUI)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PostProcessingView: View {
    @ObservedObject var processingVM: ProcessingViewModel
    @Binding var measurementDir: String
    @Binding var testSignal: String
    @EnvironmentObject var workspaceManager: WorkspaceManager
    
    // Quick Selection Toggles
    @State private var enableHeadphoneCompensation: Bool = false
    @State private var enableXCurve: Bool = false
    @State private var enableRoomCorrection: Bool = false
    @State private var enableAdvancedProcessing: Bool = false
    @State private var enableCustomEQ: Bool = false
    
    // Compensation Settings
    @State private var compensationType: String = "diffuse-field"
    @State private var customCompensationFile: String = ""
    @State private var headphoneFile: String = ""
    
    // X-Curve Settings
    @State private var xCurveAction: String = "Apply"
    @State private var xCurveType: String = "minus3db_oct"
    @State private var xCurveInCapture: Bool = false
    
    // Room Correction Settings
    @State private var roomTarget: String = ""
    @State private var micCalibration: String = ""
    
    // Processing Parameters
    @State private var decayTime: String = ""
    @State private var specificLimit: String = ""
    @State private var genericLimit: String = ""
    @State private var frCombinationMethod: String = "average"
    
    // Output Settings
    @State private var outputSampleRate: String = ""
    @State private var generatePlots: Bool = true
    @State private var exportCSV: Bool = true
    @State private var interactiveDelays: Bool = false
    
    // Validation
    @State private var canProcess: Bool = false
    @State private var validationErrors: [String] = []
    
    var compensationTypes = ["free-field", "diffuse-field", "custom"]
    var xCurveTypes = ["minus3db_oct", "minus1p5db_oct"]
    var frCombinationMethods = ["average", "weighted_average", "max", "min"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed Header with Quick Toggles
            headerSection
                .padding()
                .background(.regularMaterial, in: Rectangle())
            
            Divider()
            
            // Scrollable Details
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Workspace Info
                    workspaceInfoSection
                    
                    detailSections
                    
                    if !processingVM.log.isEmpty {
                        logSection
                    }
                }
                .padding()
            }
        }
        .onAppear(perform: validateSettings)
        .onChange(of: workspaceManager.currentWorkspace) { _ in
            validateSettings()
        }
        .onChange(of: enableHeadphoneCompensation) { _ in validateSettings() }
        .onChange(of: enableCustomEQ) { _ in validateSettings() }
        .onChange(of: enableRoomCorrection) { _ in validateSettings() }
    }
    
    // MARK: - Workspace Info Section
    
    private var workspaceInfoSection: some View {
        GroupBox("Processing Workspace") {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    
                    VStack(alignment: .leading) {
                        Text(workspaceManager.workspaceName)
                            .font(.headline)
                        
                        Text("Processing files in this workspace")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        let stats = workspaceManager.getWorkspaceStats()
                        
                        Text("\(stats.audioFiles) audio files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if stats.hasRecordings {
                            Label("Ready for processing", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Label("No recordings found", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                HStack {
                    Button("Open Workspace") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspaceManager.currentWorkspace.path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Processed audio files will be saved to:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(workspaceManager.workspaceName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post-Processing")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Select compensation types and configure processing parameters")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button("Clear Log") {
                        processingVM.clearLog()
                    }
                    .buttonStyle(.bordered)
                    .disabled(processingVM.log.isEmpty)
                    
                    Button("Save Log") {
                        if let url = savePanel(startPath: workspaceManager.currentWorkspace.path) {
                            try? processingVM.log.write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(processingVM.log.isEmpty)
                    
                    Button(action: {
                        runPostProcessing()
                    }) {
                        HStack {
                            if processingVM.isRunning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(processingVM.isRunning ? "Processing..." : "Start Post-Processing")
                        }
                    }
                    .disabled(!canProcess || processingVM.isRunning)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    if processingVM.isRunning {
                        Button("Cancel") {
                            processingVM.cancel()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // Progress Bar (if running)
            if processingVM.isRunning {
                VStack(spacing: 8) {
                    if let progress = processingVM.progress {
                        ProgressView(value: progress)
                            .frame(maxWidth: .infinity)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)
                    }
                    
                    if let remaining = processingVM.remainingTime {
                        Text(String(format: "%.1fs remaining", remaining))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Quick Selection Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                QuickToggleCard(
                    title: "Headphone Processing",
                    subtitle: "All headphone frequency corrections",
                    systemImage: "headphones",
                    isEnabled: $enableHeadphoneCompensation,
                    color: .blue
                )
                
                QuickToggleCard(
                    title: "X-Curve Processing",
                    subtitle: "SMPTE cinema curve compensation",
                    systemImage: "chart.line.uptrend.xyaxis",
                    isEnabled: $enableXCurve,
                    color: .orange
                )
                
                QuickToggleCard(
                    title: "Room Correction",
                    subtitle: "Room acoustics compensation",
                    systemImage: "house.fill",
                    isEnabled: $enableRoomCorrection,
                    color: .purple
                )
                
                QuickToggleCard(
                    title: "Advanced Settings",
                    subtitle: "Processing limits and parameters",
                    systemImage: "gearshape.2.fill",
                    isEnabled: $enableAdvancedProcessing,
                    color: .gray
                )
            }
        }
    }
    
    // MARK: - Detail Sections
    
    private var detailSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            if enableHeadphoneCompensation {
                headphoneCompensationDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if enableXCurve {
                xCurveDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if enableRoomCorrection {
                roomCorrectionDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if enableAdvancedProcessing {
                advancedProcessingDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            outputSettingsSection
        }
        .animation(.easeInOut(duration: 0.3), value: enableHeadphoneCompensation)
        .animation(.easeInOut(duration: 0.3), value: enableXCurve)
        .animation(.easeInOut(duration: 0.3), value: enableRoomCorrection)
        .animation(.easeInOut(duration: 0.3), value: enableAdvancedProcessing)
    }
    
    private var headphoneCompensationDetails: some View {
        DisclosureGroup("Headphone Processing Settings", isExpanded: .constant(true)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure frequency response corrections for your headphones")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Basic Compensation Method
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Basic Compensation Method")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Choose the primary compensation approach for your headphones")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Compensation Type", selection: $compensationType) {
                        Text("Free-Field").tag("free-field")
                        Text("Diffuse-Field").tag("diffuse-field")
                        Text("Custom File").tag("custom")
                    }
                    .pickerStyle(.segmented)
                    
                    if compensationType == "custom" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom Compensation File")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            HStack {
                                TextField("Select CSV file with compensation curve", text: $customCompensationFile)
                                Button("Browse") {
                                    if let path = openPanel(fileTypes: ["csv"]) {
                                        customCompensationFile = path
                                    }
                                }
                                Button("Workspace") {
                                    if let path = selectWorkspaceFile(fileTypes: ["csv"]) {
                                        customCompensationFile = path
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Additional EQ
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("2. Additional EQ (Optional)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Toggle("Enable", isOn: $enableCustomEQ)
                    }
                    
                    Text("Apply extra frequency response corrections on top of basic compensation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if enableCustomEQ {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Additional EQ File")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            HStack {
                                TextField("CSV file with additional frequency response corrections", text: $headphoneFile)
                                Button("Browse") {
                                    if let path = openPanel(fileTypes: ["csv"]) {
                                        headphoneFile = path
                                    }
                                }
                                Button("Workspace") {
                                    if let path = selectWorkspaceFile(fileTypes: ["csv"]) {
                                        headphoneFile = path
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            if !headphoneFile.isEmpty {
                                Text("Selected: \(URL(fileURLWithPath: headphoneFile).lastPathComponent)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var xCurveDetails: some View {
        DisclosureGroup("X-Curve Processing Settings", isExpanded: .constant(true)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SMPTE X-Curve compensation for cinema playback systems")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("X-Curve Action", selection: $xCurveAction) {
                        Text("None (Metadata Only)").tag("None")
                        Text("Apply Curve").tag("Apply")
                        Text("Remove Curve").tag("Remove")
                    }
                    .pickerStyle(.menu)
                }
                
                if xCurveAction != "None" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Curve Type")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("X-Curve Type", selection: $xCurveType) {
                            Text("-3dB/octave").tag("minus3db_oct")
                            Text("-1.5dB/octave").tag("minus1p5db_oct")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                if xCurveAction != "None" {
                    Toggle("X-Curve already present in recording", isOn: $xCurveInCapture)
                } else {
                    Toggle("Tag metadata: recorded with X-Curve", isOn: $xCurveInCapture)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var roomCorrectionDetails: some View {
        DisclosureGroup("Room Correction Settings", isExpanded: .constant(true)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Compensate for room acoustics using target curves and microphone calibration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Room Target Curve")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        TextField("CSV file with target frequency response", text: $roomTarget)
                        Button("Browse") {
                            if let path = openPanel(fileTypes: ["csv"]) {
                                roomTarget = path
                            }
                        }
                        Button("Workspace") {
                            if let path = selectWorkspaceFile(fileTypes: ["csv"]) {
                                roomTarget = path
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Microphone Calibration")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        TextField("CSV file with microphone calibration data", text: $micCalibration)
                        Button("Browse") {
                            if let path = openPanel(fileTypes: ["csv"]) {
                                micCalibration = path
                            }
                        }
                        Button("Workspace") {
                            if let path = selectWorkspaceFile(fileTypes: ["csv"]) {
                                micCalibration = path
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var advancedProcessingDetails: some View {
        DisclosureGroup("Advanced Processing Parameters", isExpanded: .constant(true)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fine-tune processing behavior with additional parameters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Decay Time Limit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        TextField("ms", text: $decayTime)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Specific Frequency Limit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        TextField("Hz", text: $specificLimit)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Generic Frequency Limit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        TextField("Hz", text: $genericLimit)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("FR Combination Method")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Picker("Method", selection: $frCombinationMethod) {
                            ForEach(frCombinationMethods, id: \.self) { method in
                                Text(method.capitalized.replacingOccurrences(of: "_", with: " "))
                                    .tag(method)
                            }
                        }
                        .frame(width: 150)
                    }
                    
                    Toggle("Interactive Speaker Delays", isOn: $interactiveDelays)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var outputSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output Settings")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sample Rate")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    TextField("Hz (leave empty for original)", text: $outputSampleRate)
                        .frame(width: 200)
                }
                
                Toggle("Generate Frequency Response Plots", isOn: $generatePlots)
                
                Toggle("Export CSV Data Files", isOn: $exportCSV)
                
                if exportCSV {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CSV files will be exported to workspace plots/ directory:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("• headphones.csv - Raw headphone frequency response")
                            Text("• compensation.csv - Applied compensation curves")
                            Text("• room-response.csv - Room correction data (if enabled)")
                            Text("• final-response.csv - Complete processed result")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processing Log")
                .font(.headline)
                .fontWeight(.semibold)
            
            ScrollView {
                Text(processingVM.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Helper Functions
    
    private func validateSettings() {
        validationErrors.removeAll()
        
        // Check workspace has recordings
        let stats = workspaceManager.getWorkspaceStats()
        if !stats.hasRecordings {
            validationErrors.append("No audio recordings found in workspace")
        }
        
        // Check test signal
        let testSignalPath = workspaceManager.getTestSignalPath()
        if testSignalPath.isEmpty {
            validationErrors.append("Test signal file required")
        } else if !FileManager.default.fileExists(atPath: testSignalPath) {
            validationErrors.append("Test signal file does not exist")
        }
        
        // Check custom compensation file
        if enableHeadphoneCompensation && compensationType == "custom" && customCompensationFile.isEmpty {
            validationErrors.append("Custom compensation file required when selected")
        }
        
        // Check headphone EQ file
        if enableCustomEQ && headphoneFile.isEmpty {
            validationErrors.append("Additional EQ file required when enabled")
        }
        
        // Check room correction files
        if enableRoomCorrection {
            if roomTarget.isEmpty {
                validationErrors.append("Room target curve required for room correction")
            }
            if micCalibration.isEmpty {
                validationErrors.append("Microphone calibration file required for room correction")
            }
        }
        
        // Check numeric fields
        if enableAdvancedProcessing {
            if !decayTime.isEmpty && Double(decayTime) == nil {
                validationErrors.append("Decay time must be a valid number")
            }
            if !specificLimit.isEmpty && Double(specificLimit) == nil {
                validationErrors.append("Specific limit must be a valid number")
            }
            if !genericLimit.isEmpty && Double(genericLimit) == nil {
                validationErrors.append("Generic limit must be a valid number")
            }
        }
        
        if !outputSampleRate.isEmpty && Int(outputSampleRate) == nil {
            validationErrors.append("Output sample rate must be a valid integer")
        }
        
        canProcess = validationErrors.isEmpty
    }
    
    private func runPostProcessing() {
        let configuration = ProcessingConfiguration(
            measurementDir: workspaceManager.currentWorkspace.path,
            testSignal: workspaceManager.getTestSignalPath(),
            channelBalance: "",
            targetLevel: "",
            playbackDevice: "",
            recordingDevice: "",
            outputChannels: [],
            inputChannels: [],
            enableCompensation: enableHeadphoneCompensation,
            headphoneEqEnabled: enableCustomEQ,
            headphoneFile: headphoneFile,
            compensationType: compensationType == "custom" ? customCompensationFile : compensationType,
            diffuseField: compensationType == "diffuse-field",
            xCurveAction: enableXCurve ? xCurveAction : "None",
            xCurveType: xCurveType,
            xCurveInCapture: xCurveInCapture,
            decayTime: enableAdvancedProcessing ? decayTime : "",
            decayEnabled: enableAdvancedProcessing && !decayTime.isEmpty,
            specificLimit: enableAdvancedProcessing ? specificLimit : "",
            specificLimitEnabled: enableAdvancedProcessing && !specificLimit.isEmpty,
            genericLimit: enableAdvancedProcessing ? genericLimit : "",
            genericLimitEnabled: enableAdvancedProcessing && !genericLimit.isEmpty,
            frCombinationMethod: frCombinationMethod,
            frCombinationEnabled: enableAdvancedProcessing,
            roomCorrection: enableRoomCorrection,
            roomTarget: roomTarget,
            micCalibration: micCalibration,
            interactiveDelays: interactiveDelays
        )
        
        processingVM.run(configuration: configuration)
        
        // If CSV export is enabled, run the export script after processing
        if exportCSV {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                exportFrequencyResponseData()
            }
        }
    }
    
    private func exportFrequencyResponseData() {
        let workspacePath = workspaceManager.currentWorkspace.path
        
        // Run the CSV export script
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let scriptsPath = Bundle.main.resourceURL?.appendingPathComponent("Scripts") ??
                             URL(fileURLWithPath: "/usr/local/bin")
            let scriptPath = scriptsPath.appendingPathComponent("export_frequency_response.py").path
            
            process.currentDirectoryURL = scriptsPath
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", scriptPath, "--measurement_dir", workspacePath]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        processingVM.logMessage("CSV export completed successfully")
                    } else {
                        processingVM.logMessage("CSV export failed with status: \(process.terminationStatus)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    processingVM.logMessage("Failed to run CSV export: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func selectWorkspaceFile(fileTypes: [String] = []) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = fileTypes.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = workspaceManager.currentWorkspace
        
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
    
    private func openPanel(fileTypes: [String] = []) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = fileTypes.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
    
    private func savePanel(startPath: String) -> URL? {
        let panel = NSSavePanel()
        panel.directoryURL = URL(fileURLWithPath: startPath)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Quick Toggle Card Component

struct QuickToggleCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isEnabled: Bool
    let color: Color
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEnabled.toggle()
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(isEnabled ? color : .secondary)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? color.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isEnabled ? color : Color.gray.opacity(0.3), lineWidth: isEnabled ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isEnabled ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

// MARK: - UTType Extension

extension UTType {
    static let csv = UTType(filenameExtension: "csv")!
}

#endif
