#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct ModernPostProcessingView: View {
    @ObservedObject var viewModel: ModernProcessingViewModel

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

    @State private var expandedSections: Set<SectionType> = [.headphoneEQ, .compensation, .processing]
    @State private var showAdvancedOptions = false
    @State private var isViewReady = false

    enum SectionType: String, CaseIterable {
        case headphoneEQ = "Headphone EQ"
        case compensation = "Compensation"
        case processing = "Processing Options"
        case roomCorrection = "Room Correction"
    }

    private let xCurveActions = ["None", "Apply X-Curve", "Remove X-Curve"]
    private let xCurveTypes = ["minus3db_oct", "minus1p5db_oct"]
    private let compensationTypes = ["diffuse", "free", "custom"]

    private var canRecordHeadphoneEQ: Bool {
        !measurementDir.isEmpty && !testSignal.isEmpty && !viewModel.isRunning
    }

    var body: some View {
        Group {
            if isViewReady {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        // Header Section
                        headerSection
                        
                        // Quick Toggle Section
                        quickToggleSection
                        
                        // Main Sections
                        ForEach(SectionType.allCases, id: \.self) { section in
                            if shouldShowSection(section) {
                                modernSection(for: section)
                            }
                        }
                        
                        // Processing Log
                        if !viewModel.log.isEmpty {
                            logSection
                        }
                    }
                    .padding(20)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .navigationTitle("Post-Processing")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Advanced") {
                            showAdvancedOptions.toggle()
                        }
                        .foregroundColor(showAdvancedOptions ? .accentColor : .secondary)
                        
                        Menu("Presets") {
                            Button("Headphone Focus") { applyHeadphonePreset() }
                            Button("Room Correction") { applyRoomCorrectionPreset() }
                            Button("Minimal Processing") { applyMinimalPreset() }
                            Button("Reset All") { resetAllSettings() }
                        }
                    }
                }
            } else {
                // Loading state
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Initializing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .navigationTitle("Post-Processing")
            }
        }
        .onAppear {
            initializeView()
        }
    }
    
    private func initializeView() {
        // Delay the view initialization to avoid state update conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Ensure default values are set to prevent binding issues
            if channelBalance.isEmpty {
                channelBalance = "off"
            }
            if compensationType.isEmpty {
                compensationType = "diffuse"
            }
            if xCurveAction.isEmpty {
                xCurveAction = "None"
            }
            if xCurveType.isEmpty {
                xCurveType = "minus3db_oct"
            }
            if frCombinationMethod.isEmpty {
                frCombinationMethod = "average"
            }
            
            // Mark view as ready after all initialization is complete
            isViewReady = true
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio Post-Processing")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Fine-tune your binaural audio with EQ, compensation, and room correction")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                processingStatusBadge
            }
            
            // Processing Pipeline Visualization
            processingPipelineView
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Quick Toggle Section
    
    private var quickToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Settings")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickToggleCard(
                    title: "Compensation",
                    description: enableCompensation ? "Active" : "Disabled",
                    icon: "waveform.path.ecg",
                    isEnabled: enableCompensation,
                    action: { enableCompensation.toggle() }
                )
                
                QuickToggleCard(
                    title: "Headphone EQ",
                    description: headphoneEqEnabled ? "Active" : "Disabled",
                    icon: "headphones",
                    isEnabled: headphoneEqEnabled,
                    action: { headphoneEqEnabled.toggle() }
                )
                
                QuickToggleCard(
                    title: "Room Correction",
                    description: roomCorrection ? "Active" : "Disabled",
                    icon: "house.and.flag",
                    isEnabled: roomCorrection,
                    action: { roomCorrection.toggle() }
                )
            }
        }
    }
    
    // MARK: - Modern Sections
    
    @ViewBuilder
    private func modernSection(for sectionType: SectionType) -> some View {
        let isExpanded = expandedSections.contains(sectionType)
        
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if isExpanded {
                        expandedSections.remove(sectionType)
                    } else {
                        expandedSections.insert(sectionType)
                    }
                }
            }) {
                HStack {
                    Image(systemName: iconForSection(sectionType))
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text(sectionType.rawValue)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if hasActiveSettings(for: sectionType) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Section Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    switch sectionType {
                    case .headphoneEQ:
                        headphoneEQContent
                    case .compensation:
                        compensationContent
                    case .processing:
                        processingOptionsContent
                    case .roomCorrection:
                        roomCorrectionContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Section Contents
    
    private var headphoneEQContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record the frequency response of your headphones using binaural microphones for personalized equalization.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(spacing: 12) {
                Button(action: recordHeadphoneEQ) {
                    HStack {
                        if viewModel.isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "record.circle")
                                .font(.title2)
                        }
                        
                        Text(viewModel.isRunning ? "Recording..." : "Record Headphone EQ")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(canRecordHeadphoneEQ ? Color.accentColor : Color.secondary)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(!canRecordHeadphoneEQ)
                
                if viewModel.isRunning {
                    progressIndicator
                }
                
                // Headphone File Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Headphone EQ File")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        TextField("Select headphone EQ file", text: $headphoneFile)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Browse") {
                            if let path = openPanel(directory: false, startPath: headphoneFile) {
                                headphoneFile = path
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var compensationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Compensation Type
            VStack(alignment: .leading, spacing: 8) {
                Text("Compensation Type")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Compensation Type", selection: $compensationType) {
                    Text("Diffuse-field").tag("diffuse")
                    Text("Free-field").tag("free")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Custom Compensation File
            if compensationType == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Compensation File")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        TextField("Select custom compensation file", text: $customCompensationFile)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Browse") {
                            if let path = openPanel(directory: false, startPath: customCompensationFile) {
                                customCompensationFile = path
                            }
                        }
                    }
                }
            }
            
            // Additional Options
            if showAdvancedOptions {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("X-Curve Processing")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("X-Curve Action", selection: $xCurveAction) {
                            ForEach(xCurveActions, id: \.self) { action in
                                Text(action).tag(action)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    if xCurveAction != "None" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("X-Curve Type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("X-Curve Type", selection: $xCurveType) {
                                ForEach(xCurveTypes, id: \.self) { type in
                                    Text(type).tag(type)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        Toggle("Capture Includes X-Curve", isOn: $xCurveInCapture)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    private var processingOptionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Channel Balance
            VStack(alignment: .leading, spacing: 8) {
                Text("Channel Balance")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Channel Balance", selection: $channelBalance) {
                    Text("Off").tag("off")
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                    Text("Average").tag("avg")
                    Text("Minimum").tag("min")
                    Text("Mids").tag("mids")
                    Text("Trend").tag("trend")
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // Target Level
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Target Level")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Button(action: {}) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Enter the desired output level in dB (e.g., -12, -18, -23). Leave empty to use peak normalization at -0.1 dB. Negative values reduce volume, positive values increase it.")
                }
                
                TextField("Target Level (dB)", text: $targetLevel)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .help("Enter the desired output level in dB (e.g., -12, -18, -23). Leave empty to use peak normalization at -0.1 dB.")
            }
            
            // Decay Time
            VStack(alignment: .leading, spacing: 8) {
                        FixedToggle(title: "Enable Decay Time Processing", isOn: $decayEnabled)
                        
                        if decayEnabled {
                            HStack {
                                Text("Decay Time (seconds)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                TextField("Seconds", text: $decayTime)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 80)
                            }
                        }
                    }
            
            // Interactive Delays
            VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Interactive Delays")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Button(action: {}) {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Interactive delays allow you to manually adjust speaker timing during processing.")
                            }
                            
                            // REPLACE Toggle with FixedToggle:
                            FixedToggle(title: "Enable Interactive Delay Adjustment", isOn: $interactiveDelays)
                        }
                        
                        // Rest of interactive delays content stays the same...
                        if interactiveDelays {
                    // Your existing interactive delays content
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Manual delay adjustment will be available during processing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.blue)
                            Text("Real-time adjustment mode")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    private var roomCorrectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apply room correction using measured room response to compensate for acoustic characteristics.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(spacing: 12) {
                // Room Target File
                VStack(alignment: .leading, spacing: 8) {
                    Text("Room Target File")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        TextField("Select room target file", text: $roomTarget)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Browse") {
                            if let path = openPanel(directory: false, startPath: roomTarget) {
                                roomTarget = path
                            }
                        }
                    }
                }
                
                // Mic Calibration File
                VStack(alignment: .leading, spacing: 8) {
                    Text("Microphone Calibration File")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        TextField("Select mic calibration file", text: $micCalibration)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Browse") {
                            if let path = openPanel(directory: false, startPath: micCalibration) {
                                micCalibration = path
                            }
                        }
                    }
                }
                
                if showAdvancedOptions {
                    VStack(spacing: 12) {
                        // Specific Limit
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Enable Specific Frequency Limit", isOn: $specificLimitEnabled)
                            
                            if specificLimitEnabled {
                                HStack {
                                    Text("Frequency (Hz)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    TextField("Hz", text: $specificLimit)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 100)
                                }
                            }
                        }
                        
                        // Generic Limit
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Enable Generic Frequency Limit", isOn: $genericLimitEnabled)
                            
                            if genericLimitEnabled {
                                HStack {
                                    Text("Frequency (Hz)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    TextField("Hz", text: $genericLimit)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 100)
                                }
                            }
                        }
                        
                        // FR Combination
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Enable Frequency Response Combination", isOn: $frCombinationEnabled)
                            
                            if frCombinationEnabled {
                                Picker("Combination Method", selection: $frCombinationMethod) {
                                    Text("Average").tag("average")
                                    Text("Conservative").tag("conservative")
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    
    // MARK: - Supporting Views
    
    private var delayFileStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            let positionsFile = URL(fileURLWithPath: measurementDir).appendingPathComponent("speaker_positions.json")
            let delaysFile = URL(fileURLWithPath: measurementDir).appendingPathComponent("speaker_delays.json")
            let hasPositions = FileManager.default.fileExists(atPath: positionsFile.path)
            let hasDelays = FileManager.default.fileExists(atPath: delaysFile.path)
            
            HStack {
                Image(systemName: hasDelays ? "checkmark.circle.fill" : (hasPositions ? "clock.circle" : "exclamationmark.triangle"))
                    .foregroundColor(hasDelays ? .green : (hasPositions ? .orange : .red))
                
                VStack(alignment: .leading, spacing: 2) {
                    if hasDelays {
                        Text("Using pre-calculated delays")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("speaker_delays.json found")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if hasPositions {
                        Text("Will calculate delays from positions")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("speaker_positions.json found")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No delay or position files found")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Default delays will be used")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if hasDelays || hasPositions {
                    Button("View") {
                        // Could open the delay/position file for viewing
                        if hasDelays {
                            NSWorkspace.shared.open(delaysFile)
                        } else {
                            NSWorkspace.shared.open(positionsFile)
                        }
                    }
                    .font(.caption)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
    
    private var processingStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isRunning ? Color.green : Color.blue)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isRunning)
            
            Text(viewModel.isRunning ? "Processing" : "Ready")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }
    
    private var processingPipelineView: some View {
        HStack(spacing: 8) {
            PipelineStage(title: "EQ", isActive: headphoneEqEnabled)
            PipelineArrow()
            PipelineStage(title: "Compensation", isActive: enableCompensation)
            PipelineArrow()
            PipelineStage(title: "Room", isActive: roomCorrection)
            PipelineArrow()
            PipelineStage(title: "Output", isActive: true)
        }
        .padding(.vertical, 8)
    }
    
    private var progressIndicator: some View {
        VStack(spacing: 8) {
            if let progress = viewModel.progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 4)
                
                Text("\(Int(progress * 100))% complete")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 4)
                
                Text("Initializing...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processing Log")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Clear") {
                    viewModel.clearLog()
                }
                .font(.caption)
            }
            
            ScrollView {
                Text(viewModel.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 150)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func shouldShowSection(_ section: SectionType) -> Bool {
        switch section {
        case .roomCorrection:
            return roomCorrection
        default:
            return true
        }
    }
    
    private func iconForSection(_ section: SectionType) -> String {
        switch section {
        case .headphoneEQ:
            return "headphones"
        case .compensation:
            return "waveform.path.ecg"
        case .processing:
            return "slider.horizontal.3"
        case .roomCorrection:
            return "house.and.flag"
        }
    }
    
    private func hasActiveSettings(for section: SectionType) -> Bool {
        switch section {
        case .headphoneEQ:
            return headphoneEqEnabled
        case .compensation:
            return enableCompensation
        case .processing:
            return decayEnabled || !channelBalance.isEmpty || !targetLevel.isEmpty
        case .roomCorrection:
            return roomCorrection
        }
    }
    
    private func recordHeadphoneEQ() {
        viewModel.recordHeadphoneEQ(measurementDir: measurementDir,
                                    testSignal: testSignal,
                                    playbackDevice: playbackDevice,
                                    recordingDevice: recordingDevice)
    }
    
    // MARK: - Preset Functions
    
    private func applyHeadphonePreset() {
        enableCompensation = true
        headphoneEqEnabled = true
        compensationType = "diffuse"
        roomCorrection = false
    }
    
    private func applyRoomCorrectionPreset() {
        enableCompensation = true
        headphoneEqEnabled = false
        roomCorrection = true
    }
    
    private func applyMinimalPreset() {
        enableCompensation = false
        headphoneEqEnabled = false
        roomCorrection = false
        decayEnabled = false
    }
    
    private func resetAllSettings() {
        enableCompensation = false
        headphoneEqEnabled = false
        headphoneFile = ""
        compensationType = "diffuse"
        customCompensationFile = ""
        xCurveAction = "None"
        roomCorrection = false
        roomTarget = ""
        micCalibration = ""
        channelBalance = ""
        targetLevel = ""
        decayEnabled = false
        decayTime = ""
        specificLimitEnabled = false
        specificLimit = ""
        genericLimitEnabled = false
        genericLimit = ""
        frCombinationEnabled = false
        frCombinationMethod = "average"
        interactiveDelays = false
    }
    
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

// MARK: - Supporting Components

struct QuickToggleCard: View {
    let title: String
    let description: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(isEnabled ? .accentColor : .secondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PipelineStage: View {
    let title: String
    let isActive: Bool
    
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor : Color.secondary)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
}

struct PipelineArrow: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

struct FixedToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Button(action: {
                isOn.toggle()
                print("DEBUG: \(title) toggled to: \(isOn)")
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .foregroundColor(isOn ? .accentColor : .secondary)
                        .font(.system(size: 16))
                    
                    Text(title)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
    }
}

#endif
