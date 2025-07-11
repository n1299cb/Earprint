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
        
        // Create default workspace path with date-based name
        let defaultName = "Workspace \(Date().formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
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
    
    // MARK: - Workspace Operations
    
    /// Clear all files in the current workspace
    func clearCurrentWorkspace() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: currentWorkspace, includingPropertiesForKeys: nil)
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
        
        // Also clear subdirectories like plots
        if FileManager.default.fileExists(atPath: plotsDirectory.path) {
            try FileManager.default.removeItem(at: plotsDirectory)
        }
        
        // Recreate the plots directory
        try FileManager.default.createDirectory(at: plotsDirectory, withIntermediateDirectories: true)
        
        // Trigger UI refresh
        refreshWorkspaceStats()
    }
    
    /// Generate test data in the plots directory
    func generateTestData() {
        let testDataGenerator = TestDataGenerator()
        testDataGenerator.generateAllTestFiles(in: plotsDirectory)
        
        // Trigger UI refresh
        refreshWorkspaceStats()
    }
    
    /// Force refresh of workspace statistics and UI
    func refreshWorkspaceStats() {
        // Trigger SwiftUI to recalculate any views that depend on workspace stats
        objectWillChange.send()
    }
    
    // MARK: - Test Signal Management
    
    /// Get available test signals from Scripts/data directory
    func loadAvailableTestSignals() {
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
            // Check if source file actually exists first
            guard FileManager.default.fileExists(atPath: testSignalInfo.url.path) else {
                print("Test signal source file does not exist: \(testSignalInfo.url.path)")
                return nil
            }
            
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
        let workspaceName = name ?? "Workspace \(Date().formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        let sanitizedName = sanitizeFilename(workspaceName)
        let newWorkspaceURL = workspacesDirectory.appendingPathComponent(sanitizedName)
        
        do {
            try FileManager.default.createDirectory(at: newWorkspaceURL, withIntermediateDirectories: true)
            
            // Create subdirectories
            try FileManager.default.createDirectory(at: newWorkspaceURL.appendingPathComponent("plots"),
                                                  withIntermediateDirectories: true)
            
            // Switch to new workspace
            currentWorkspace = newWorkspaceURL
            self.workspaceName = sanitizedName
            
            loadAvailableWorkspaces()
            
            print("Created new workspace: \(sanitizedName)")
            
            // Note: Test signals will be handled by Python backend when needed
            // No need to copy test signals during workspace creation
            
        } catch {
            print("Failed to create workspace: \(error)")
        }
    }
    
    /// Switch to an existing workspace
    func switchToWorkspace(_ workspaceInfo: WorkspaceInfo) {
        // Only switch if it's actually different
        guard workspaceInfo.url != currentWorkspace else { return }
        
        currentWorkspace = workspaceInfo.url
        workspaceName = workspaceInfo.name
        
        print("Switched to workspace: \(workspaceInfo.name)")
        
        // Trigger UI refresh only once at the end
        objectWillChange.send()
    }
    
    /// Delete a workspace
    func deleteWorkspace(_ workspaceInfo: WorkspaceInfo) {
        do {
            try FileManager.default.removeItem(at: workspaceInfo.url)
            print("Deleted workspace: \(workspaceInfo.name)")
            
            // Reload available workspaces after deletion
            loadAvailableWorkspaces()
            
            // Don't handle switching here - let the UI detect and fix invalid states
            // This prevents cascading updates during deletion
            
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

// MARK: - Data Models

struct WorkspaceInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
    let creationDate: Date
    let isCurrent: Bool
    
    // Implement Equatable based on URL since that's the unique identifier
    static func == (lhs: WorkspaceInfo, rhs: WorkspaceInfo) -> Bool {
        return lhs.url == rhs.url
    }
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
