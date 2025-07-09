import Foundation
import SwiftUI

/// Manages the application's temporary workspace and export functionality
@MainActor
class WorkspaceManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentWorkspace: URL
    @Published var availableWorkspaces: [WorkspaceInfo] = []
    @Published var workspaceName: String = ""
    @Published var availableTestSignals: [TestSignalInfo] = []
    @Published var defaultTestSignal: String = ""
    
    // MARK: - Constants
    private let appSupportURL: URL
    private let workspacesDirectoryName = "Workspaces"
    private let bundledScriptsURL: URL?
    private let bundledDataURL: URL?
    
    // MARK: - Computed Properties
    var workspacesDirectory: URL {
        appSupportURL.appendingPathComponent(workspacesDirectoryName)
    }
    
    var plotsDirectory: URL {
        currentWorkspace.appendingPathComponent("plots")
    }
    
    var hasRecordings: Bool {
        hasFile("headphones.wav") || hasFiles(["FL,FR.wav", "responses.wav", "hrir.wav"])
    }
    
    var hasProcessedData: Bool {
        hasFile("hrir.wav") || hasFile("hesuvi.wav")
    }
    
    var hasCSVData: Bool {
        guard FileManager.default.fileExists(atPath: plotsDirectory.path) else { return false }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: plotsDirectory, includingPropertiesForKeys: nil)
            return files.contains { $0.pathExtension.lowercased() == "csv" }
        } catch {
            return false
        }
    }
    
    // MARK: - Initialization
    init() {
        // Create app support directory
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
                                            .appendingPathComponent("Earprint")
        
        // Initialize all stored properties first
        self.appSupportURL = appSupportURL
        self.bundledScriptsURL = Bundle.main.resourceURL?.appendingPathComponent("Scripts")
        self.bundledDataURL = self.bundledScriptsURL?.appendingPathComponent("data")
        
        // Create the workspaces directory path (can't use computed property yet)
        let workspacesDirectoryURL = appSupportURL.appendingPathComponent("Workspaces")
        
        // Create default workspace path
        let defaultName = "Current Session"
        let defaultWorkspaceURL = workspacesDirectoryURL.appendingPathComponent(defaultName)
        
        // Initialize remaining stored properties
        self.currentWorkspace = defaultWorkspaceURL
        self.workspaceName = defaultName
        
        // Now that all stored properties are initialized, we can create directories
        do {
            try fileManager.createDirectory(at: workspacesDirectoryURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: defaultWorkspaceURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: defaultWorkspaceURL.appendingPathComponent("plots"), withIntermediateDirectories: true)
        } catch {
            print("Failed to create workspace directories: \(error)")
        }
        
        // Load workspaces and test signals after everything is set up
        loadAvailableWorkspaces()
        loadAvailableTestSignals()
    }
    
    // MARK: - Test Signal Management
    
    /// Get available test signals from Scripts/data directory
    private func loadAvailableTestSignals() {
        guard let dataURL = bundledDataURL,
              FileManager.default.fileExists(atPath: dataURL.path) else {
            availableTestSignals = []
            return
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: dataURL, includingPropertiesForKeys: nil)
            
            var signals: [TestSignalInfo] = []
            
            // Look for sweep files (both .wav and .pkl)
            for file in contents {
                let filename = file.lastPathComponent
                let ext = file.pathExtension.lowercased()
                
                if (ext == "wav" || ext == "pkl") && filename.contains("sweep") {
                    let info = TestSignalInfo(
                        name: filename,
                        url: file,
                        type: ext == "pkl" ? .pickle : .wav,
                        isDefault: filename.contains("sweep-6.15s-48000Hz-32bit-2.93Hz-24000Hz")
                    )
                    signals.append(info)
                }
            }
            
            // Sort by type (pkl first, then wav) and name
            availableTestSignals = signals.sorted { lhs, rhs in
                if lhs.type != rhs.type {
                    return lhs.type == .pickle
                }
                return lhs.name < rhs.name
            }
            
            // Set default test signal
            if let defaultSignal = availableTestSignals.first(where: { $0.isDefault }) {
                defaultTestSignal = defaultSignal.url.path
            } else if let firstSignal = availableTestSignals.first {
                defaultTestSignal = firstSignal.url.path
            }
            
        } catch {
            print("Failed to load test signals: \(error)")
            availableTestSignals = []
        }
    }
    
    /// Copy a test signal to the current workspace
    func copyTestSignalToWorkspace(_ testSignalInfo: TestSignalInfo) -> String? {
        let destinationURL = currentWorkspace.appendingPathComponent("test.\(testSignalInfo.type.rawValue)")
        
        do {
            // Remove existing test signal if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: testSignalInfo.url, to: destinationURL)
            return destinationURL.path
        } catch {
            print("Failed to copy test signal: \(error)")
            return nil
        }
    }
    
    /// Get the default test signal path (from bundled data or workspace)
    func getTestSignalPath() -> String {
        // First check if test signal exists in workspace
        let workspaceTestWav = currentWorkspace.appendingPathComponent("test.wav")
        let workspaceTestPkl = currentWorkspace.appendingPathComponent("test.pkl")
        
        if FileManager.default.fileExists(atPath: workspaceTestPkl.path) {
            return workspaceTestPkl.path
        } else if FileManager.default.fileExists(atPath: workspaceTestWav.path) {
            return workspaceTestWav.path
        }
        
        // Fall back to default bundled test signal
        return defaultTestSignal
    }
    
    // MARK: - Workspace Management
    
    /// Create a new workspace with optional name
    func createNewWorkspace(name: String? = nil) {
        let workspaceName = name ?? "Workspace \(Date().formatted(.dateTime.month().day().hour().minute()))"
        let sanitizedName = sanitizeFilename(workspaceName)
        let newWorkspaceURL = workspacesDirectory.appendingPathComponent(sanitizedName)
        
        do {
            try FileManager.default.createDirectory(at: newWorkspaceURL, withIntermediateDirectories: true)
            
            // Create subdirectories
            try FileManager.default.createDirectory(at: newWorkspaceURL.appendingPathComponent("plots"),
                                                  withIntermediateDirectories: true)
            
            // Copy default test signal to new workspace
            if let defaultSignal = availableTestSignals.first(where: { $0.isDefault }) ?? availableTestSignals.first {
                _ = copyTestSignalToWorkspace(defaultSignal)
            }
            
            // Switch to new workspace
            currentWorkspace = newWorkspaceURL
            self.workspaceName = sanitizedName
            
            loadAvailableWorkspaces()
            
        } catch {
            print("Failed to create workspace: \(error)")
        }
    }
    
    /// Switch to an existing workspace
    func switchToWorkspace(_ workspaceInfo: WorkspaceInfo) {
        currentWorkspace = workspaceInfo.url
        workspaceName = workspaceInfo.name
    }
    
    /// Delete a workspace
    func deleteWorkspace(_ workspaceInfo: WorkspaceInfo) {
        guard workspaceInfo.url != currentWorkspace else {
            print("Cannot delete current workspace")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: workspaceInfo.url)
            loadAvailableWorkspaces()
        } catch {
            print("Failed to delete workspace: \(error)")
        }
    }
    
    /// Rename current workspace
    func renameCurrentWorkspace(to newName: String) {
        let sanitizedName = sanitizeFilename(newName)
        let newURL = workspacesDirectory.appendingPathComponent(sanitizedName)
        
        guard newURL != currentWorkspace else { return }
        
        do {
            try FileManager.default.moveItem(at: currentWorkspace, to: newURL)
            currentWorkspace = newURL
            workspaceName = sanitizedName
            loadAvailableWorkspaces()
        } catch {
            print("Failed to rename workspace: \(error)")
        }
    }
    
    // MARK: - Export Functions
    
    /// Export entire workspace to a user-selected location
    func exportWorkspace(to destinationURL: URL) async throws {
        // Capture main actor values before background work
        let workspaceURL = currentWorkspace
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    
                    // Create destination directory if it doesn't exist
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    
                    // Copy all files from workspace
                    let contents = try fileManager.contentsOfDirectory(at: workspaceURL, includingPropertiesForKeys: nil)
                    
                    for item in contents {
                        let destination = destinationURL.appendingPathComponent(item.lastPathComponent)
                        
                        // Remove existing file if present
                        if fileManager.fileExists(atPath: destination.path) {
                            try fileManager.removeItem(at: destination)
                        }
                        
                        try fileManager.copyItem(at: item, to: destination)
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Export specific file types
    func exportFiles(types: ExportType, to destinationURL: URL) async throws {
        // Capture main actor values before background work
        let filesToExport = getFilesForExport(types: types)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    
                    for (sourceURL, filename) in filesToExport {
                        let destinationFileURL = destinationURL.appendingPathComponent(filename)
                        
                        if fileManager.fileExists(atPath: destinationFileURL.path) {
                            try fileManager.removeItem(at: destinationFileURL)
                        }
                        
                        try fileManager.copyItem(at: sourceURL, to: destinationFileURL)
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Get workspace statistics for display
    func getWorkspaceStats() -> WorkspaceStats {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var fileCount = 0
        var audioFiles = 0
        var csvFiles = 0
        
        func calculateSize(at url: URL) {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
                return
            }
            
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                        fileCount += 1
                        
                        let ext = fileURL.pathExtension.lowercased()
                        if ext == "wav" || ext == "aiff" || ext == "flac" {
                            audioFiles += 1
                        } else if ext == "csv" {
                            csvFiles += 1
                        }
                    }
                } catch {
                    // Skip files we can't read
                }
            }
        }
        
        calculateSize(at: currentWorkspace)
        
        return WorkspaceStats(
            totalSize: totalSize,
            fileCount: fileCount,
            audioFiles: audioFiles,
            csvFiles: csvFiles,
            hasRecordings: hasRecordings,
            hasProcessedData: hasProcessedData,
            hasCSVData: hasCSVData
        )
    }
    
    // MARK: - Private Functions
    
    private func loadAvailableWorkspaces() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: workspacesDirectory,
                                                                       includingPropertiesForKeys: [.creationDateKey])
            
            var workspaces: [WorkspaceInfo] = []
            
            for url in contents {
                guard url.hasDirectoryPath else { continue }
                
                let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey])
                let creationDate = resourceValues?.creationDate ?? Date()
                
                let info = WorkspaceInfo(
                    name: url.lastPathComponent,
                    url: url,
                    creationDate: creationDate,
                    isCurrent: url == currentWorkspace
                )
                
                workspaces.append(info)
            }
            
            availableWorkspaces = workspaces.sorted { $0.creationDate > $1.creationDate }
            
        } catch {
            print("Failed to load workspaces: \(error)")
            availableWorkspaces = []
        }
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalidChars).joined(separator: "-")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func hasFile(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: currentWorkspace.appendingPathComponent(filename).path)
    }
    
    private func hasFiles(_ filenames: [String]) -> Bool {
        filenames.contains { hasFile($0) }
    }
    
    private func getFilesForExport(types: ExportType) -> [(URL, String)] {
        var files: [(URL, String)] = []
        let fileManager = FileManager.default
        
        // Audio files
        if types.contains(.audio) {
            let audioExtensions = ["wav", "aiff", "flac"]
            if let contents = try? fileManager.contentsOfDirectory(at: currentWorkspace, includingPropertiesForKeys: nil) {
                for url in contents {
                    if audioExtensions.contains(url.pathExtension.lowercased()) {
                        files.append((url, url.lastPathComponent))
                    }
                }
            }
        }
        
        // CSV files
        if types.contains(.csv) {
            if let contents = try? fileManager.contentsOfDirectory(at: plotsDirectory, includingPropertiesForKeys: nil) {
                for url in contents {
                    if url.pathExtension.lowercased() == "csv" {
                        files.append((url, url.lastPathComponent))
                    }
                }
            }
        }
        
        // Processed files
        if types.contains(.processed) {
            let processedFiles = ["hrir.wav", "hesuvi.wav", "responses.wav"]
            for filename in processedFiles {
                let url = currentWorkspace.appendingPathComponent(filename)
                if fileManager.fileExists(atPath: url.path) {
                    files.append((url, filename))
                }
            }
        }
        
        return files
    }
}

// MARK: - Data Models

struct WorkspaceInfo: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let creationDate: Date
    let isCurrent: Bool
}

struct WorkspaceStats {
    let totalSize: Int64
    let fileCount: Int
    let audioFiles: Int
    let csvFiles: Int
    let hasRecordings: Bool
    let hasProcessedData: Bool
    let hasCSVData: Bool
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

struct ExportType: OptionSet {
    let rawValue: Int
    
    static let audio = ExportType(rawValue: 1 << 0)
    static let csv = ExportType(rawValue: 1 << 1)
    static let processed = ExportType(rawValue: 1 << 2)
    
    static let all: ExportType = [.audio, .csv, .processed]
}

// MARK: - Test Signal Data Models

struct TestSignalInfo: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let type: TestSignalType
    let isDefault: Bool
}

enum TestSignalType: String, CaseIterable {
    case wav = "wav"
    case pickle = "pkl"
    
    var displayName: String {
        switch self {
        case .wav: return "WAV Audio"
        case .pickle: return "Pickled Signal"
        }
    }
}
