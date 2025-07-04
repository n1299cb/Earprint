#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct ModernExecutionView: View {
    @ObservedObject var viewModel: ModernProcessingViewModel
    var measurementDir: String
    var testSignal: String
    var channelBalance: String
    var targetLevel: String
    var playbackDevice: String
    var recordingDevice: String
    var outputChannels: [Int]
    var inputChannels: [Int]
    var selectedLayout: String = ""
    @Binding var enableCompensation: Bool
    @Binding var headphoneEqEnabled: Bool
    @Binding var headphoneFile: String
    @Binding var compensationType: String
    @Binding var customCompensationFile: String
    @Binding var diffuseField: Bool
    @Binding var xCurveAction: String
    @Binding var xCurveType: String
    @Binding var xCurveInCapture: Bool
    var decayTime: String
    var decayEnabled: Bool
    var specificLimit: String
    var specificLimitEnabled: Bool
    var genericLimit: String
    var genericLimitEnabled: Bool
    var frCombinationMethod: String
    var frCombinationEnabled: Bool
    var roomCorrection: Bool
    var roomTarget: String
    var micCalibration: String
    var interactiveDelays: Bool

    @StateObject private var recordingVM = RecordingViewModel()
    @State private var showExportDialog = false

    private var canRunProcessing: Bool {
        !measurementDir.isEmpty && !testSignal.isEmpty && !viewModel.isRunning
    }

    private var hasResults: Bool {
        FileManager.default.fileExists(atPath: URL(fileURLWithPath: measurementDir).appendingPathComponent("hesuvi.wav").path)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Processing Control Section
                processingControlSection
                
                // Progress and Status
                if viewModel.isRunning {
                    progressSection
                }
                
                // Quick Actions
                quickActionsSection
                
                // Results and Export
                if hasResults || !recordingVM.latestRecording.isEmpty {
                    resultsSection
                }
                
                // Processing Log
                if !viewModel.log.isEmpty {
                    logSection
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .navigationTitle("Processing")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isRunning {
                    Button("Cancel") {
                        viewModel.cancel()
                    }
                    .foregroundColor(.red)
                }
                
                Button("Clear Log") {
                    viewModel.clearLog()
                }
                .disabled(viewModel.log.isEmpty)
            }
        }
        .onAppear(perform: validatePaths)
        .onChange(of: viewModel.isRunning) { running in
            if !running { validatePaths() }
        }
        .alert("Error", isPresented: $recordingVM.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recordingVM.errorMessage)
        }
    }
    
    // MARK: - Processing Control Section
    
    private var processingControlSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio Processing")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Process binaural recordings into HRIR/BRIR files")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                processingStatusIndicator
            }
            
            // Main Processing Button
            Button(action: runProcessing) {
                HStack {
                    if viewModel.isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                    }
                    
                    Text(viewModel.isRunning ? "Processing..." : "Start Processing")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canRunProcessing ? Color.accentColor : Color.secondary)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!canRunProcessing)
            
            // Processing Configuration Summary
            if !viewModel.isRunning {
                configurationSummary
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Processing Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let remaining = viewModel.remainingTime {
                    Text(String(format: "%.1fs remaining", remaining))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                }
            }
            
            // Progress Bar
            VStack(spacing: 8) {
                if let progress = viewModel.progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.separatorColor))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * progress, height: 8)
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                } else {
                    // Indeterminate progress
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 8)
                    
                    Text("Initializing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Tools")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack(spacing: 12) {
                QuickRecordingCard(
                    title: "Launch Recorder",
                    description: "Manual recording control",
                    icon: "record.circle",
                    isEnabled: !viewModel.isRunning,
                    action: {
                        viewModel.record(measurementDir: measurementDir,
                                         testSignal: testSignal,
                                         playbackDevice: playbackDevice,
                                         recordingDevice: recordingDevice,
                                         outputFile: nil)
                    }
                )
                
                QuickRecordingCard(
                    title: "Capture Wizard",
                    description: "Guided recording process",
                    icon: "wand.and.stars",
                    isEnabled: !viewModel.isRunning && !selectedLayout.isEmpty,
                    action: {
                        viewModel.captureWizard(layout: selectedLayout, dir: measurementDir)
                    }
                )
                
                QuickRecordingCard(
                    title: "Auto Log",
                    description: viewModel.autoLog ? "Logging enabled" : "Enable logging",
                    icon: viewModel.autoLog ? "doc.text.fill" : "doc.text",
                    isEnabled: true,
                    action: { viewModel.autoLog.toggle() }
                )
            }
            
            // Log file configuration
            if viewModel.autoLog {
                HStack {
                    TextField("Log file path", text: $viewModel.logFile)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Browse") {
                        if let url = savePanel(startPath: measurementDir) {
                            viewModel.logFile = url.path
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Results Section
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results & Export")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Latest Recording Info
                if !recordingVM.latestRecording.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest Recording")
                                .font(.headline)
                            
                            TextField("Recording name", text: $recordingVM.recordingName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        Button(action: saveRecording) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save")
                            }
                        }
                        .disabled(!recordingVM.measurementHasFiles || recordingVM.latestRecording.isEmpty)
                    }
                    
                    Divider()
                }
                
                // Export Options
                HStack(spacing: 12) {
                    Button(action: exportHesuvi) {
                        HStack {
                            Image(systemName: "headphones")
                            Text("Export HeSuVi")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(hasResults ? Color.accentColor : Color.secondary)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .disabled(!hasResults)
                    
                    Button(action: saveLog) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Save Log")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(!viewModel.log.isEmpty ? Color.secondary : Color.secondary.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .disabled(viewModel.log.isEmpty)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
    
    // MARK: - Log Section
    
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processing Log")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Clear") {
                    viewModel.clearLog()
                }
                .font(.caption)
            }
            
            ScrollView {
                ScrollViewReader { proxy in
                    Text(viewModel.log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("logBottom")
                        .onAppear {
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                        .onChange(of: viewModel.log) { _ in
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                }
            }
            .frame(height: 200)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Supporting Views
    
    private var processingStatusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isRunning ? Color.green : (canRunProcessing ? Color.blue : Color.secondary))
                .frame(width: 12, height: 12)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isRunning)
            
            Text(viewModel.isRunning ? "Running" : (canRunProcessing ? "Ready" : "Not Ready"))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }
    
    private var configurationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration Summary")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ConfigSummaryItem(label: "Layout", value: selectedLayout.isEmpty ? "Not set" : selectedLayout)
                ConfigSummaryItem(label: "Compensation", value: enableCompensation ? "Enabled" : "Disabled")
                ConfigSummaryItem(label: "Room Correction", value: roomCorrection ? "Enabled" : "Disabled")
                ConfigSummaryItem(label: "Headphone EQ", value: headphoneEqEnabled ? "Enabled" : "Disabled")
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Helper Functions
    
    private func runProcessing() {
        viewModel.run(
            measurementDir: measurementDir,
            testSignal: testSignal,
            channelBalance: channelBalance,
            targetLevel: targetLevel,
            playbackDevice: playbackDevice,
            recordingDevice: recordingDevice,
            outputChannels: outputChannels,
            inputChannels: inputChannels,
            enableCompensation: enableCompensation,
            headphoneEqEnabled: headphoneEqEnabled,
            headphoneFile: headphoneFile,
            compensationType: compensationType == "custom" ? customCompensationFile : compensationType,
            diffuseField: diffuseField,
            xCurveAction: xCurveAction,
            xCurveType: xCurveType,
            xCurveInCapture: xCurveInCapture,
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
            interactiveDelays: interactiveDelays
        )
    }
    
    private func saveRecording() {
        if let path = saveDirectoryPanel(startPath: measurementDir) {
            recordingVM.saveLatest(from: measurementDir, to: path) { viewModel.logMessage($0) }
        }
    }
    
    private func exportHesuvi() {
        if let dest = savePanel(startPath: measurementDir) {
            viewModel.exportHesuviPreset(measurementDir: measurementDir, destination: dest.path)
        }
    }
    
    private func saveLog() {
        if let url = savePanel(startPath: measurementDir) {
            try? viewModel.log.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func validatePaths() {
        recordingVM.validatePaths(measurementDir)
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

struct QuickRecordingCard: View {
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
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
}

struct ConfigSummaryItem: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
        }
    }
}

#endif
