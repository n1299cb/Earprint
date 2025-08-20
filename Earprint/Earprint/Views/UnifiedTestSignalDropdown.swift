import SwiftUI

// MARK: - Test Signal Option Model
struct TestSignalOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let type: TestSignalSourceType
    let isValid: Bool
    
    var displayName: String {
        switch type {
        case .bundled:
            return "📦 \(name)"
        case .workspace:
            return "📁 \(name)"
        case .custom:
            return "🔧 \(name)"
        }
    }
}

enum TestSignalSourceType {
    case bundled
    case workspace
    case custom
}

// MARK: - Unified Test Signal Dropdown
struct UnifiedTestSignalDropdown: View {
    @EnvironmentObject var workspaceManager: WorkspaceManager
    @EnvironmentObject var configurationVM: ConfigurationViewModel
    
    let title: String
    let showDescription: Bool
    let recordingMode: Bool  // Add this parameter
    
    @State private var availableSignals: [TestSignalOption] = []
    @State private var selectedSignalId: UUID?
    
    init(title: String = "Test Signal", showDescription: Bool = true, recordingMode: Bool = false) {
        self.title = title
        self.showDescription = showDescription
        self.recordingMode = recordingMode
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            if !title.isEmpty {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Status indicator
                    if let selectedSignal = selectedSignal {
                        HStack(spacing: 4) {
                            Image(systemName: selectedSignal.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(selectedSignal.isValid ? .green : .red)
                                .font(.caption)
                            
                            Text(selectedSignal.isValid ? "Valid" : "Missing")
                                .font(.caption)
                                .foregroundColor(selectedSignal.isValid ? .green : .red)
                        }
                    }
                }
            }
            
            // Dropdown
            Menu {
                ForEach(availableSignals) { signal in
                    Button(action: {
                        selectSignal(signal)
                    }) {
                        HStack {
                            Text(signal.displayName)
                            Spacer()
                            if signal.id == selectedSignalId {
                                Image(systemName: "checkmark")
                            }
                            if !signal.isValid {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                if !availableSignals.isEmpty {
                    Divider()
                }
                
                Button("Browse Custom File...") {
                    browseCustomFile()
                }
            } label: {
                HStack {
                    Text(selectedSignal?.displayName ?? "Select test signal...")
                        .foregroundColor(selectedSignal != nil ? .primary : .secondary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Description
            if showDescription, let selectedSignal = selectedSignal {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedSignal.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    
                    switch selectedSignal.type {
                    case .workspace:
                        Text("Located in current workspace")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    case .bundled:
                        Text("Bundled with application")
                            .font(.caption2)
                            .foregroundColor(.green)
                    case .custom:
                        Text("Custom file")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            loadAvailableSignals()
            loadSelectedSignal()
        }
        .onReceive(workspaceManager.objectWillChange) {
            loadAvailableSignals()
        }
        .onReceive(configurationVM.objectWillChange) {
            loadSelectedSignal()
        }
    }
    
    // MARK: - Computed Properties
    private var selectedSignal: TestSignalOption? {
        availableSignals.first { $0.id == selectedSignalId }
    }
    
    // MARK: - Helper Methods
    private func loadAvailableSignals() {
        var signals: [TestSignalOption] = []
        
        // Add bundled signals (these come from WorkspaceManager.availableTestSignals)
        let bundledSignals = workspaceManager.availableTestSignals
        print("DEBUG: Found \(bundledSignals.count) bundled signals")
        for signalInfo in bundledSignals {
            // Filter out .pkl files in recording mode
            if recordingMode && signalInfo.url.pathExtension.lowercased() == "pkl" {
                print("DEBUG: Skipping pkl file in recording mode: \(signalInfo.name)")
                continue
            }
            
            print("DEBUG: Bundled signal: \(signalInfo.name) at \(signalInfo.url.path)")
            let option = TestSignalOption(
                name: signalInfo.name,
                path: signalInfo.url.path,
                type: .bundled,
                isValid: FileManager.default.fileExists(atPath: signalInfo.url.path)
            )
            signals.append(option)
            print("DEBUG: Added bundled signal option: \(option.displayName), valid: \(option.isValid)")
        }
        
        // Add workspace signals (look for test signal files in current workspace)
        let workspaceSignals = findWorkspaceTestSignals()
        print("DEBUG: Found \(workspaceSignals.count) workspace signals")
        for signalPath in workspaceSignals {
            // Filter out .pkl files in recording mode
            if recordingMode && URL(fileURLWithPath: signalPath).pathExtension.lowercased() == "pkl" {
                print("DEBUG: Skipping workspace pkl file in recording mode: \(signalPath)")
                continue
            }
            
            let url = URL(fileURLWithPath: signalPath)
            let option = TestSignalOption(
                name: url.lastPathComponent,
                path: signalPath,
                type: .workspace,
                isValid: FileManager.default.fileExists(atPath: signalPath)
            )
            signals.append(option)
            print("DEBUG: Added workspace signal: \(option.displayName)")
        }
        
        // Add current custom signal if it's not already in the list
        let currentSignalPath = configurationVM.appConfiguration.defaultTestSignal
        print("DEBUG: Current signal path from config: '\(currentSignalPath)'")
        if !currentSignalPath.isEmpty && !signals.contains(where: { $0.path == currentSignalPath }) {
            // Filter out .pkl files in recording mode
            if recordingMode && URL(fileURLWithPath: currentSignalPath).pathExtension.lowercased() == "pkl" {
                print("DEBUG: Skipping current pkl file in recording mode, will auto-select first valid signal")
            } else {
                let url = URL(fileURLWithPath: currentSignalPath)
                let option = TestSignalOption(
                    name: url.lastPathComponent,
                    path: currentSignalPath,
                    type: .custom,
                    isValid: FileManager.default.fileExists(atPath: currentSignalPath)
                )
                signals.append(option)
                print("DEBUG: Added custom signal: \(option.displayName)")
            }
        }
        
        // Sort: bundled first, then workspace, then custom
        signals.sort { lhs, rhs in
            if lhs.type != rhs.type {
                switch (lhs.type, rhs.type) {
                case (.bundled, _): return true
                case (_, .bundled): return false
                case (.workspace, .custom): return true
                case (.custom, .workspace): return false
                default: return false
                }
            }
            return lhs.name < rhs.name
        }
        
        availableSignals = signals
        print("DEBUG: Total signals available: \(signals.count)")
    }
    
    private func loadSelectedSignal() {
        let currentPath = configurationVM.appConfiguration.defaultTestSignal
        print("DEBUG: Loading selected signal, current path: '\(currentPath)'")
        print("DEBUG: Available signals: \(availableSignals.map { $0.path })")
        
        // Find matching signal or use first bundled signal as default
        if let matchingSignal = availableSignals.first(where: { $0.path == currentPath }) {
            selectedSignalId = matchingSignal.id
            print("DEBUG: Found matching signal: \(matchingSignal.displayName)")
        } else if let firstBundled = availableSignals.first(where: { $0.type == .bundled }) {
            selectedSignalId = firstBundled.id
            print("DEBUG: Using first bundled signal as default: \(firstBundled.displayName)")
            // Update configuration to match
            configurationVM.updateDefaultTestSignal(firstBundled.path)
        } else if let firstAvailable = availableSignals.first {
            // Fallback to any available signal if no bundled signals found
            selectedSignalId = firstAvailable.id
            print("DEBUG: Using first available signal as default: \(firstAvailable.displayName)")
            configurationVM.updateDefaultTestSignal(firstAvailable.path)
        } else {
            print("DEBUG: No signals found to use as default")
        }
    }
    
    private func selectSignal(_ signal: TestSignalOption) {
        selectedSignalId = signal.id
        configurationVM.updateDefaultTestSignal(signal.path)
    }
    
    private func findWorkspaceTestSignals() -> [String] {
        let workspacePath = workspaceManager.currentWorkspace.path
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: workspacePath) else {
            return []
        }
        
        return contents
            .filter { filename in
                let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
                let isAudioFile = ext == "wav" || ext == "pkl"
                let looksLikeTestSignal = filename.lowercased().contains("sweep") ||
                                         filename.lowercased().contains("test") ||
                                         filename.lowercased().contains("signal")
                return isAudioFile && looksLikeTestSignal
            }
            .map { filename in
                URL(fileURLWithPath: workspacePath).appendingPathComponent(filename).path
            }
            .sorted()
    }
    
    private func browseCustomFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select Test Signal"
        
        if panel.runModal() == .OK, let url = panel.url {
            let customOption = TestSignalOption(
                name: url.lastPathComponent,
                path: url.path,
                type: .custom,
                isValid: true
            )
            
            // Add to available signals if not already present
            if !availableSignals.contains(where: { $0.path == url.path }) {
                availableSignals.append(customOption)
                availableSignals.sort { lhs, rhs in
                    if lhs.type != rhs.type {
                        switch (lhs.type, rhs.type) {
                        case (.bundled, _): return true
                        case (_, .bundled): return false
                        case (.workspace, .custom): return true
                        case (.custom, .workspace): return false
                        default: return false
                        }
                    }
                    return lhs.name < rhs.name
                }
            }
            
            selectSignal(customOption)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct UnifiedTestSignalDropdown_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedTestSignalDropdown()
            .environmentObject(WorkspaceManager())
            .environmentObject(ConfigurationViewModel())
            .padding()
    }
}
#endif
