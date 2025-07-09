import SwiftUI

struct TestSignalSelector: View {
    @EnvironmentObject var workspaceManager: WorkspaceManager
    @Binding var testSignal: String
    @State private var showingSignalSheet = false
    @State private var selectedSignalInfo: TestSignalInfo?
    
    var currentSignalName: String {
        if testSignal.isEmpty {
            return "No test signal selected"
        }
        
        let url = URL(fileURLWithPath: testSignal)
        return url.lastPathComponent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Test Signal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Browse Bundled Signals") {
                    showingSignalSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            HStack {
                TextField("Test signal path", text: $testSignal)
                    .textFieldStyle(.roundedBorder)
                
                Button("Browse File") {
                    selectCustomTestSignal()
                }
                .buttonStyle(.bordered)
            }
            
            if !testSignal.isEmpty {
                HStack {
                    Image(systemName: testSignal.contains(".pkl") ? "doc.badge.gearshape" : "waveform")
                        .foregroundColor(.secondary)
                    
                    Text(currentSignalName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if FileManager.default.fileExists(atPath: testSignal) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .onAppear {
            // Set default test signal if none selected
            if testSignal.isEmpty {
                testSignal = workspaceManager.getTestSignalPath()
            }
        }
        .sheet(isPresented: $showingSignalSheet) {
            testSignalSheet
        }
    }
    
    private var testSignalSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Select Test Signal")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose from bundled test signals or use a custom file")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                if workspaceManager.availableTestSignals.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.orange)
                        
                        Text("No bundled test signals found")
                            .font(.headline)
                        
                        Text("The Scripts/data directory may not be properly bundled with the app. You can still use custom test signal files.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(workspaceManager.availableTestSignals) { signalInfo in
                        TestSignalRow(
                            signalInfo: signalInfo,
                            isSelected: selectedSignalInfo?.id == signalInfo.id,
                            onSelect: { selectedSignalInfo = signalInfo }
                        )
                    }
                    .frame(height: 300)
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        showingSignalSheet = false
                        selectedSignalInfo = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Use Selected Signal") {
                        if let selected = selectedSignalInfo {
                            useTestSignal(selected)
                        }
                        showingSignalSheet = false
                        selectedSignalInfo = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSignalInfo == nil)
                }
            }
            .padding()
            .navigationTitle("Test Signals")
        }
    }
    
    private func selectCustomTestSignal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select Test Signal"
        
        if panel.runModal() == .OK, let url = panel.url {
            testSignal = url.path
        }
    }
    
    private func useTestSignal(_ signalInfo: TestSignalInfo) {
        // Copy to workspace and use that path
        if let workspacePath = workspaceManager.copyTestSignalToWorkspace(signalInfo) {
            testSignal = workspacePath
        } else {
            // Fall back to direct path to bundled file
            testSignal = signalInfo.url.path
        }
    }
}

struct TestSignalRow: View {
    let signalInfo: TestSignalInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(signalInfo.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if signalInfo.isDefault {
                            Text("DEFAULT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    HStack {
                        Text(signalInfo.type.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if signalInfo.type == .pickle {
                            Text("Recommended")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                VStack {
                    Image(systemName: signalInfo.type == .pickle ? "doc.badge.gearshape.fill" : "waveform")
                        .font(.title3)
                        .foregroundColor(signalInfo.type == .pickle ? .blue : .orange)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(isSelected ? .blue.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
