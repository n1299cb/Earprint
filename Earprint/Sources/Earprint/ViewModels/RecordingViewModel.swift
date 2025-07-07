#if canImport(SwiftUI)
import SwiftUI
import Foundation

// MARK: - Recording Models
struct RecordingInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let dateModified: Date
    let size: Int64
    let isDirectory: Bool
    
    static func == (lhs: RecordingInfo, rhs: RecordingInfo) -> Bool {
        lhs.path == rhs.path
    }
}

struct FileValidationResult {
    let isValid: Bool
    let errorMessage: String?
    let suggestions: [String]
}

// MARK: - Recording State
enum RecordingState: Equatable {
    case idle
    case scanning
    case validating
    case saving
    case error(String)
    
    var isProcessing: Bool {
        switch self {
        case .scanning, .validating, .saving:
            return true
        default:
            return false
        }
    }
}

// MARK: - Enhanced RecordingViewModel
@MainActor
final class RecordingViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var state: RecordingState = .idle
    @Published var hasFiles: Bool = false
    @Published var recordings: [RecordingInfo] = []
    @Published var latestRecording: RecordingInfo?
    @Published var validationResults: [String: FileValidationResult] = [:]
    @Published var selectedRecordings: Set<String> = []
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    
    // MARK: - Computed Properties
    var recordingName: String {
        latestRecording?.name ?? "No recordings"
    }
    
    var measurementHasFiles: Bool {
        hasFiles
    }
    
    var canSave: Bool {
        !selectedRecordings.isEmpty && !state.isProcessing
    }
    
    // MARK: - Private Properties
    private let fileManager = FileManager.default
    
    // MARK: - Public Methods
    func validatePaths(_ measurementDir: String) {
        guard !measurementDir.isEmpty else {
            state = .idle
            hasFiles = false
            recordings = []
            latestRecording = nil
            return
        }
        
        state = .scanning
        
        Task {
            await scanDirectory(measurementDir)
        }
    }
    
    func refreshRecordings(_ measurementDir: String) {
        validatePaths(measurementDir)
    }
    
    func saveFiles(
        files: [URL],
        measurementDir: String,
        destination: String,
        completion: @escaping (String) -> Void
    ) {
        guard !state.isProcessing else {
            completion("Save operation already in progress")
            return
        }
        
        state = .saving
        
        Task {
            await performSaveOperation(
                files: files,
                destination: destination,
                completion: completion
            )
        }
    }
    
    func saveLatest(
        from measurementDir: String,
        to destination: String,
        completion: @escaping (String) -> Void
    ) {
        guard let latest = latestRecording else {
            completion("No latest recording found")
            return
        }
        
        let sourceURL = URL(fileURLWithPath: latest.path)
        saveFiles(
            files: [sourceURL],
            measurementDir: measurementDir,
            destination: destination,
            completion: completion
        )
    }
    
    func saveSelected(
        from measurementDir: String,
        to destination: String,
        completion: @escaping (String) -> Void
    ) {
        let selectedFiles = recordings
            .filter { selectedRecordings.contains($0.name) }
            .map { URL(fileURLWithPath: $0.path) }
        
        guard !selectedFiles.isEmpty else {
            completion("No files selected")
            return
        }
        
        saveFiles(
            files: selectedFiles,
            measurementDir: measurementDir,
            destination: destination,
            completion: completion
        )
    }
    
    func deleteRecording(name: String, completion: @escaping (String) -> Void) {
        guard let recording = recordings.first(where: { $0.name == name }) else {
            completion("Recording not found: \(name)")
            return
        }
        
        let url = URL(fileURLWithPath: recording.path)
        
        do {
            try fileManager.removeItem(at: url)
            recordings.removeAll { $0.name == name }
            selectedRecordings.remove(name)
            
            if latestRecording?.name == name {
                latestRecording = recordings.max { $0.dateModified < $1.dateModified }
            }
            
            hasFiles = !recordings.isEmpty
            completion("Deleted \(name)")
        } catch {
            completion("Failed to delete \(name): \(error.localizedDescription)")
        }
    }
    
    func toggleSelection(for recordingName: String) {
        if selectedRecordings.contains(recordingName) {
            selectedRecordings.remove(recordingName)
        } else {
            selectedRecordings.insert(recordingName)
        }
    }
    
    func selectAll() {
        selectedRecordings = Set(recordings.map { $0.name })
    }
    
    func deselectAll() {
        selectedRecordings.removeAll()
    }
    
    // MARK: - Legacy Support Methods
    func updateLatestRecording(_ measurementDir: String) {
        validatePaths(measurementDir)
    }
    
    // MARK: - File Utility Methods
    func getRecordingSize(_ recording: RecordingInfo) -> String {
        ByteCountFormatter.string(fromByteCount: recording.size, countStyle: .file)
    }
    
    func getRecordingAge(_ recording: RecordingInfo) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: recording.dateModified, relativeTo: Date())
    }
    
    func isAudioFile(_ recording: RecordingInfo) -> Bool {
        let audioExtensions = ["wav", "aif", "aiff", "mp3", "flac", "m4a"]
        let ext = URL(fileURLWithPath: recording.path).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }
    
    func getMeasurementType(_ recording: RecordingInfo) -> String {
        let name = recording.name.lowercased()
        
        if name.contains("headphone") {
            return "Headphone EQ"
        } else if name.contains("room") {
            return "Room Response"
        } else if name.contains("sweep") {
            return "Test Sweep"
        } else if isAudioFile(recording) {
            return "Audio Recording"
        } else if name.hasSuffix(".csv") {
            return "Measurement Data"
        } else if name.hasSuffix(".json") {
            return "Configuration"
        } else {
            return "Unknown"
        }
    }
    
    func getValidationStatus(_ recording: RecordingInfo) -> String {
        guard let result = validationResults[recording.name] else {
            return "Not validated"
        }
        
        if result.isValid {
            return result.suggestions.isEmpty ? "Valid" : result.suggestions.first ?? "Valid"
        } else {
            return result.errorMessage ?? "Invalid"
        }
    }
    
    func getRecordingIcon(_ recording: RecordingInfo) -> String {
        if recording.isDirectory {
            return "folder"
        } else if isAudioFile(recording) {
            return "waveform"
        } else {
            let name = recording.name.lowercased()
            if name.hasSuffix(".csv") {
                return "tablecells"
            } else if name.hasSuffix(".json") {
                return "doc.text"
            } else if name.hasSuffix(".log") || name.hasSuffix(".txt") {
                return "doc.plaintext"
            } else {
                return "doc"
            }
        }
    }
    
    // MARK: - Private Methods
    private func scanDirectory(_ measurementDir: String) async {
        let dirURL = URL(fileURLWithPath: measurementDir)
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isDirectoryKey
                ],
                options: [.skipsHiddenFiles]
            )
            
            var recordingInfos: [RecordingInfo] = []
            
            for url in contents {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isDirectoryKey
                    ])
                    
                    let info = RecordingInfo(
                        name: url.lastPathComponent,
                        path: url.path,
                        dateModified: resourceValues.contentModificationDate ?? Date.distantPast,
                        size: Int64(resourceValues.fileSize ?? 0),
                        isDirectory: resourceValues.isDirectory ?? false
                    )
                    recordingInfos.append(info)
                } catch {
                    // Skip files that can't be read
                    continue
                }
            }
            
            await MainActor.run {
                self.recordings = recordingInfos.sorted { $0.dateModified > $1.dateModified }
                self.latestRecording = recordingInfos.max { $0.dateModified < $1.dateModified }
                self.hasFiles = !recordingInfos.isEmpty
                self.state = .idle
            }
            
            // Start validation in background
            await validateRecordings()
            
        } catch {
            await MainActor.run {
                self.recordings = []
                self.latestRecording = nil
                self.hasFiles = false
                self.state = .error("Failed to scan directory: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.showErrorAlert = true
            }
        }
    }
    
    private func validateRecordings() async {
        await MainActor.run {
            self.state = .validating
        }
        
        for recording in recordings {
            let result = performFileValidation(at: recording.path)
            await MainActor.run {
                self.validationResults[recording.name] = result
            }
        }
        
        await MainActor.run {
            self.state = .idle
        }
    }
    
    private func performFileValidation(at path: String) -> FileValidationResult {
        let url = URL(fileURLWithPath: path)
        var suggestions: [String] = []
        
        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            return FileValidationResult(
                isValid: false,
                errorMessage: "File does not exist",
                suggestions: ["Check file path", "Refresh directory"]
            )
        }
        
        // Check if it's a wave file
        if url.pathExtension.lowercased() == "wav" {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: path)
                if let fileSize = attributes[.size] as? Int64, fileSize == 0 {
                    suggestions.append("File is empty")
                    return FileValidationResult(
                        isValid: false,
                        errorMessage: "Empty audio file",
                        suggestions: suggestions
                    )
                }
            } catch {
                return FileValidationResult(
                    isValid: false,
                    errorMessage: "Cannot read file attributes",
                    suggestions: ["Check file permissions"]
                )
            }
            
            return FileValidationResult(isValid: true, errorMessage: nil, suggestions: [])
        }
        
        // Check for common measurement files
        let commonExtensions = ["csv", "json", "txt", "log"]
        if commonExtensions.contains(url.pathExtension.lowercased()) {
            suggestions.append("Measurement data file")
            return FileValidationResult(isValid: true, errorMessage: nil, suggestions: suggestions)
        }
        
        // Unknown file type
        suggestions.append("Unknown file type")
        return FileValidationResult(
            isValid: true,
            errorMessage: nil,
            suggestions: suggestions
        )
    }
    
    private func performSaveOperation(
        files: [URL],
        destination: String,
        completion: @escaping (String) -> Void
    ) async {
        let destinationURL = URL(fileURLWithPath: destination)
        
        do {
            // Create destination directory if needed
            try fileManager.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            var savedCount = 0
            var errors: [String] = []
            
            for fileURL in files {
                let destURL = destinationURL.appendingPathComponent(fileURL.lastPathComponent)
                
                do {
                    // Remove existing file if it exists
                    if fileManager.fileExists(atPath: destURL.path) {
                        try fileManager.removeItem(at: destURL)
                    }
                    
                    try fileManager.copyItem(at: fileURL, to: destURL)
                    savedCount += 1
                } catch {
                    errors.append("Failed to copy \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                self.state = .idle
                
                if errors.isEmpty {
                    completion("Successfully saved \(savedCount) file(s) to \(destination)")
                } else {
                    let errorMessage = "Saved \(savedCount) files with \(errors.count) errors:\n" + errors.joined(separator: "\n")
                    completion(errorMessage)
                }
            }
            
        } catch {
            await MainActor.run {
                self.state = .error("Save operation failed")
                self.errorMessage = error.localizedDescription
                self.showErrorAlert = true
                completion("Failed to create destination directory: \(error.localizedDescription)")
            }
        }
    }
}

#else
// Non-macOS stub implementation
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var hasFiles: Bool = false
    @Published var recordings: [RecordingInfo] = []
    @Published var latestRecording: RecordingInfo?
    @Published var validationResults: [String: FileValidationResult] = [:]
    @Published var selectedRecordings: Set<String> = []
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    
    var recordingName: String { "No recordings" }
    var measurementHasFiles: Bool { false }
    var canSave: Bool { false }
    
    func validatePaths(_ measurementDir: String) {}
    func refreshRecordings(_ measurementDir: String) {}
    func saveFiles(files: [URL], measurementDir: String, destination: String, completion: @escaping (String) -> Void) {}
    func saveLatest(from measurementDir: String, to destination: String, completion: @escaping (String) -> Void) {}
    func saveSelected(from measurementDir: String, to destination: String, completion: @escaping (String) -> Void) {}
    func deleteRecording(name: String, completion: @escaping (String) -> Void) {}
    func toggleSelection(for recordingName: String) {}
    func selectAll() {}
    func deselectAll() {}
    func updateLatestRecording(_ measurementDir: String) {}
    func getRecordingSize(_ recording: RecordingInfo) -> String { "" }
    func getRecordingAge(_ recording: RecordingInfo) -> String { "" }
    func isAudioFile(_ recording: RecordingInfo) -> Bool { false }
    func getMeasurementType(_ recording: RecordingInfo) -> String { "" }
    func getValidationStatus(_ recording: RecordingInfo) -> String { "" }
    func getRecordingIcon(_ recording: RecordingInfo) -> String { "" }
}
#endif
