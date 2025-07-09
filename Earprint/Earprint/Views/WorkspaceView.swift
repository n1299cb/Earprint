#if canImport(SwiftUI)
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject private var workspaceManager: WorkspaceManager
    @State private var showingExportSheet = false
    @State private var showingNewWorkspaceSheet = false
    @State private var showingWorkspaceList = false
    @State private var newWorkspaceName = ""
    @State private var exportTypes: ExportType = .all
    @State private var isExporting = false
    @State private var exportError: String?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerSection
            
            // Workspace Status
            workspaceStatusSection
            
            // Quick Actions
            quickActionsSection
            
            // Workspace Management
            workspaceManagementSection
            
            Spacer()
        }
        .padding()
        .navigationTitle("Workspace")
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showingNewWorkspaceSheet) {
            newWorkspaceSheet
        }
        .sheet(isPresented: $showingWorkspaceList) {
            workspaceListSheet
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workspace")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { showingWorkspaceList = true }) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }
            
            Text("Manage your measurement sessions and export results")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Workspace Status Section
    
    private var workspaceStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Workspace")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(workspaceManager.workspaceName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            
            let stats = workspaceManager.getWorkspaceStats()
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatusCard(
                    title: "Files",
                    value: "\(stats.fileCount)",
                    subtitle: "\(stats.formattedSize)",
                    icon: "doc.fill",
                    color: .blue
                )
                
                StatusCard(
                    title: "Audio",
                    value: "\(stats.audioFiles)",
                    subtitle: "recordings",
                    icon: "waveform",
                    color: stats.hasRecordings ? .green : .gray
                )
                
                StatusCard(
                    title: "Data",
                    value: "\(stats.csvFiles)",
                    subtitle: "CSV files",
                    icon: "chart.line.uptrend.xyaxis",
                    color: stats.hasCSVData ? .orange : .gray
                )
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ActionButton(
                    title: "Export All",
                    subtitle: "Save complete workspace",
                    icon: "square.and.arrow.up.fill",
                    color: .blue,
                    action: { showingExportSheet = true }
                )
                .disabled(!workspaceManager.hasRecordings && !workspaceManager.hasProcessedData)
                
                ActionButton(
                    title: "New Session",
                    subtitle: "Start fresh workspace",
                    icon: "plus.circle.fill",
                    color: .green,
                    action: { showingNewWorkspaceSheet = true }
                )
                
                ActionButton(
                    title: "Generate Test Data",
                    subtitle: "Create sample CSV files",
                    icon: "wand.and.stars",
                    color: .purple,
                    action: { generateTestData() }
                )
                
                ActionButton(
                    title: "Clear Workspace",
                    subtitle: "Remove all files",
                    icon: "trash.fill",
                    color: .red,
                    action: { clearWorkspace() }
                )
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Workspace Management Section
    
    private var workspaceManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Workspaces")
                .font(.headline)
                .fontWeight(.semibold)
            
            if workspaceManager.availableWorkspaces.isEmpty {
                Text("No other workspaces")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(workspaceManager.availableWorkspaces.prefix(3)) { workspace in
                        WorkspaceRow(
                            workspace: workspace,
                            onSwitch: { workspaceManager.switchToWorkspace(workspace) },
                            onDelete: { workspaceManager.deleteWorkspace(workspace) }
                        )
                    }
                    
                    if workspaceManager.availableWorkspaces.count > 3 {
                        Button("View All Workspaces") {
                            showingWorkspaceList = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Export Sheet
    
    private var exportSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export Workspace")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose what to export from your current workspace")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Options")
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        ExportOptionRow(
                            title: "Audio Files",
                            subtitle: "Original recordings and processed audio",
                            isSelected: exportTypes.contains(.audio),
                            onToggle: {
                                if exportTypes.contains(.audio) {
                                    exportTypes.remove(.audio)
                                } else {
                                    exportTypes.insert(.audio)
                                }
                            }
                        )
                        
                        ExportOptionRow(
                            title: "CSV Data",
                            subtitle: "Frequency response and analysis data",
                            isSelected: exportTypes.contains(.csv),
                            onToggle: {
                                if exportTypes.contains(.csv) {
                                    exportTypes.remove(.csv)
                                } else {
                                    exportTypes.insert(.csv)
                                }
                            }
                        )
                        
                        ExportOptionRow(
                            title: "Processed Files",
                            subtitle: "HRIR, Hesuvi, and final outputs",
                            isSelected: exportTypes.contains(.processed),
                            onToggle: {
                                if exportTypes.contains(.processed) {
                                    exportTypes.remove(.processed)
                                } else {
                                    exportTypes.insert(.processed)
                                }
                            }
                        )
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                
                if let error = exportError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        showingExportSheet = false
                        exportError = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Export") {
                        exportWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(exportTypes.isEmpty || isExporting)
                }
            }
            .padding()
            .navigationTitle("Export")
        }
    }
    
    // MARK: - New Workspace Sheet
    
    private var newWorkspaceSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create New Workspace")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start a fresh measurement session")
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workspace Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Enter workspace name", text: $newWorkspaceName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        showingNewWorkspaceSheet = false
                        newWorkspaceName = ""
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Create") {
                        workspaceManager.createNewWorkspace(name: newWorkspaceName.isEmpty ? nil : newWorkspaceName)
                        showingNewWorkspaceSheet = false
                        newWorkspaceName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("New Workspace")
        }
    }
    
    // MARK: - Workspace List Sheet
    
    private var workspaceListSheet: some View {
        NavigationView {
            List {
                ForEach(workspaceManager.availableWorkspaces) { workspace in
                    WorkspaceRow(
                        workspace: workspace,
                        onSwitch: {
                            workspaceManager.switchToWorkspace(workspace)
                            showingWorkspaceList = false
                        },
                        onDelete: { workspaceManager.deleteWorkspace(workspace) }
                    )
                }
            }
            .navigationTitle("All Workspaces")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        showingWorkspaceList = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func exportWorkspace() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Export Workspace"
        panel.prompt = "Export"
        panel.nameFieldStringValue = workspaceManager.workspaceName
        
        if panel.runModal() == .OK, let url = panel.url {
            isExporting = true
            exportError = nil
            
            Task {
                do {
                    if exportTypes == .all {
                        try await workspaceManager.exportWorkspace(to: url)
                    } else {
                        try await workspaceManager.exportFiles(types: exportTypes, to: url)
                    }
                    
                    await MainActor.run {
                        isExporting = false
                        showingExportSheet = false
                    }
                } catch {
                    await MainActor.run {
                        isExporting = false
                        exportError = "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            isExporting = false
        }
        #endif
    }
    
    private func generateTestData() {
        let testDataGenerator = TestDataGenerator()
        testDataGenerator.generateAllTestFiles(in: workspaceManager.plotsDirectory)
    }
    
    private func clearWorkspace() {
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

// MARK: - Supporting Views

struct StatusCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceRow: View {
    let workspace: WorkspaceInfo
    let onSwitch: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(workspace.creationDate.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if workspace.isCurrent {
                Text("Current")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            } else {
                HStack {
                    Button("Switch", action: onSwitch)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    
                    Button("Delete", action: onDelete)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExportOptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(isSelected ? .blue.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Test Data Generator

class TestDataGenerator {
    func generateAllTestFiles(in directory: URL) {
        // Create plots directory if it doesn't exist
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        generateHeadphoneTestData(in: directory)
        generateHRIRTestData(in: directory)
        generateRoomCorrectionData(in: directory)
        generateBeforeAfterData(in: directory)
    }
    
    private func generateHeadphoneTestData(in directory: URL) {
        let frequencies = stride(from: 20.0, through: 20000.0, by: 20.0).map { $0 }
        let csvPath = directory.appendingPathComponent("headphones-test.csv")
        
        var csvContent = "frequency,left_db,right_db,left_right_diff\n"
        
        for freq in frequencies {
            // Create realistic headphone response
            let bassRolloff = freq < 100 ? -12 * log10(freq / 100) : 0
            let presencePeak = 6 * exp(-pow((log10(freq) - log10(3000)) / 0.3, 2))
            let trebleRolloff = freq > 10000 ? -6 * log10(freq / 10000) : 0
            let noise = Double.random(in: -0.5...0.5)
            
            let leftResponse = bassRolloff + presencePeak + trebleRolloff + noise
            let rightResponse = leftResponse + Double.random(in: -0.2...0.2)
            let diff = leftResponse - rightResponse
            
            csvContent += "\(freq),\(leftResponse),\(rightResponse),\(diff)\n"
        }
        
        try? csvContent.write(to: csvPath, atomically: true, encoding: .utf8)
    }
    
    private func generateHRIRTestData(in directory: URL) {
        let frequencies = stride(from: 20.0, through: 20000.0, by: 25.0).map { $0 }
        let csvPath = directory.appendingPathComponent("hrir-test.csv")
        
        var csvContent = "frequency,FL_left,FL_right,FR_left,FR_right\n"
        
        for freq in frequencies {
            let baseResponse = -3 * log10(freq / 1000)
            
            let flLeft = baseResponse + 3 * exp(-pow((log10(freq) - log10(100)) / 0.5, 2)) + Double.random(in: -0.3...0.3)
            let flRight = baseResponse + Double.random(in: -0.3...0.3)
            let frLeft = baseResponse + Double.random(in: -0.3...0.3)
            let frRight = baseResponse + 2 * exp(-pow((log10(freq) - log10(5000)) / 0.3, 2)) + Double.random(in: -0.3...0.3)
            
            csvContent += "\(freq),\(flLeft),\(flRight),\(frLeft),\(frRight)\n"
        }
        
        try? csvContent.write(to: csvPath, atomically: true, encoding: .utf8)
    }
    
    private func generateRoomCorrectionData(in directory: URL) {
        let frequencies = stride(from: 20.0, through: 20000.0, by: 30.0).map { $0 }
        let csvPath = directory.appendingPathComponent("room-correction-test.csv")
        
        var csvContent = "frequency,room_measured,target_response,correction_needed\n"
        
        for freq in frequencies {
            let roomResponse = 5 * exp(-pow((log10(freq) - log10(60)) / 0.4, 2)) - 8 * exp(-pow((log10(freq) - log10(15000)) / 0.3, 2))
            let targetResponse = -1 * log10(freq / 1000)
            let correction = targetResponse - roomResponse
            
            csvContent += "\(freq),\(roomResponse),\(targetResponse),\(correction)\n"
        }
        
        try? csvContent.write(to: csvPath, atomically: true, encoding: .utf8)
    }
    
    private func generateBeforeAfterData(in directory: URL) {
        let frequencies = stride(from: 20.0, through: 20000.0, by: 35.0).map { $0 }
        let csvPath = directory.appendingPathComponent("before-after-test.csv")
        
        var csvContent = "frequency,before_processing,after_processing,improvement\n"
        
        for freq in frequencies {
            let beforeResponse = -8 * log10(freq / 100) + 8 * exp(-pow((log10(freq) - log10(3000)) / 0.2, 2)) - 15 * exp(-pow((log10(freq) - log10(12000)) / 0.25, 2))
            let afterResponse = -2 * log10(freq / 1000) + Double.random(in: -0.4...0.4)
            let improvement = afterResponse - beforeResponse
            
            csvContent += "\(freq),\(beforeResponse),\(afterResponse),\(improvement)\n"
        }
        
        try? csvContent.write(to: csvPath, atomically: true, encoding: .utf8)
    }
}

#else
// Non-macOS stub implementation
struct WorkspaceView: View {
    var body: some View {
        Text("Workspace view is only available on macOS")
            .padding()
    }
}
#endif
