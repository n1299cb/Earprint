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
    @State private var showingTestDataAlert = false
    @State private var refreshTrigger = UUID()
    
    // Remove the hasAnyWorkspaces property since we're handling this in body now
    
    private var stats: WorkspaceStats {
        return workspaceManager.getWorkspaceStats()
    }
    
    var body: some View {
        if workspaceManager.availableWorkspaces.isEmpty {
            // No workspaces available at all - force user to create one
            noWorkspaceView
        } else {
            // Has workspaces available - show normal view
            workspaceContentView
                .onAppear {
                    checkAndFixInvalidWorkspace()
                }
                .onChange(of: workspaceManager.availableWorkspaces) { _ in
                    checkAndFixInvalidWorkspace()
                }
        }
    }
    
    // MARK: - Auto-fix Helper
    
    private func checkAndFixInvalidWorkspace() {
        // Check if current workspace path is invalid and auto-fix it
        if !FileManager.default.fileExists(atPath: workspaceManager.currentWorkspace.path) && !workspaceManager.availableWorkspaces.isEmpty {
            if let firstValidWorkspace = workspaceManager.availableWorkspaces.first {
                print("Auto-switching from invalid workspace to: \(firstValidWorkspace.name)")
                workspaceManager.switchToWorkspace(firstValidWorkspace)
            }
        }
    }
    
    // MARK: - No Workspace View
    
    private var noWorkspaceView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                
                Text("No Workspace Found")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("You need to create a workspace to continue using Earprint")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Create New Workspace") {
                showingNewWorkspaceSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Workspace")
        .sheet(isPresented: $showingNewWorkspaceSheet) {
            newWorkspaceSheet
                .frame(width: 500, height: 400)
        }
    }
    
    // MARK: - Main Workspace Content
    
    private var workspaceContentView: some View {
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
                .frame(width: 500, height: 400)
        }
        .sheet(isPresented: $showingWorkspaceList) {
            workspaceListSheet
        }
        .alert("Test Data Generated", isPresented: $showingTestDataAlert) {
            Button("OK") { }
        } message: {
            Text("Sample CSV files have been created in the plots directory.")
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
            
            let currentStats = stats
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatusCard(
                    title: "Files",
                    value: "\(currentStats.fileCount)",
                    subtitle: "\(currentStats.formattedSize)",
                    icon: "doc.fill",
                    color: .blue
                )
                
                StatusCard(
                    title: "Audio",
                    value: "\(currentStats.audioFiles)",
                    subtitle: "recordings",
                    icon: "waveform",
                    color: currentStats.hasRecordings ? .green : .gray
                )
                
                StatusCard(
                    title: "Data",
                    value: "\(currentStats.csvFiles)",
                    subtitle: "CSV files",
                    icon: "chart.line.uptrend.xyaxis",
                    color: currentStats.hasCSVData ? .orange : .gray
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
                .disabled(!stats.hasRecordings && !stats.hasProcessedData)
                
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
                            onDelete: { workspaceManager.deleteWorkspace(workspace) },
                            onRename: workspace.isCurrent ? { newName in
                                workspaceManager.renameCurrentWorkspace(to: newName)
                            } : nil
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
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                
                Text("Create New Workspace")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start a fresh measurement session with a clean workspace")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Enter workspace name (optional)", text: $newWorkspaceName)
                    .textFieldStyle(.roundedBorder)
                
                Text("If left empty, a name will be generated automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    showingNewWorkspaceSheet = false
                    newWorkspaceName = ""
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Create Workspace") {
                    workspaceManager.createNewWorkspace(name: newWorkspaceName.isEmpty ? nil : newWorkspaceName)
                    showingNewWorkspaceSheet = false
                    newWorkspaceName = ""
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(32)
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
                        onDelete: { workspaceManager.deleteWorkspace(workspace) },
                        onRename: workspace.isCurrent ? { newName in
                            workspaceManager.renameCurrentWorkspace(to: newName)
                        } : nil
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
        workspaceManager.generateTestData()
        showingTestDataAlert = true
    }
    
    private func clearWorkspace() {
        #if canImport(AppKit)
        let alert = NSAlert()
        alert.messageText = "Clear Workspace"
        alert.informativeText = "This will permanently delete all files in the current workspace, including subdirectories. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try workspaceManager.clearCurrentWorkspace()
            } catch {
                print("Failed to clear workspace: \(error)")
                
                // Show error alert
                let errorAlert = NSAlert()
                errorAlert.messageText = "Clear Failed"
                errorAlert.informativeText = "Failed to clear workspace: \(error.localizedDescription)"
                errorAlert.alertStyle = .critical
                errorAlert.runModal()
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
    let onRename: ((String) -> Void)?
    
    @State private var showingRenameAlert = false
    @State private var newName = ""
    
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
                HStack(spacing: 8) {
                    Text("Current")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    
                    if onRename != nil {
                        Button("Rename") {
                            newName = workspace.name
                            showingRenameAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
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
        .alert("Rename Workspace", isPresented: $showingRenameAlert) {
            TextField("Workspace name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if !newName.isEmpty {
                    onRename?(newName)
                }
            }
        } message: {
            Text("Enter a new name for this workspace")
        }
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

#else
// Non-macOS stub implementation
struct WorkspaceView: View {
    var body: some View {
        Text("Workspace view is only available on macOS")
            .padding()
    }
}
#endif
