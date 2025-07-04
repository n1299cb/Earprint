#if canImport(SwiftUI)
import SwiftUI
import Foundation

@MainActor
final class ModernRecordingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var measurementHasFiles: Bool = false
    @Published var latestRecording: String = ""
    @Published var recordingName: String = ""
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    
    // MARK: - Enhanced Properties
    @Published var recordingFiles: [RecordingFile] = []
    @Published var totalFileSize: Int64 = 0
    @Published var recordingCount: Int = 0
    @Published var isValidating: Bool = false
    
    // MARK: - Recording File Model
    struct RecordingFile: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let path: String
        let size: Int64
        let dateCreated: Date
        let fileType: FileType
        
        enum FileType: String, CaseIterable {
            case audio = "Audio"
            case measurement = "Measurement"
            case configuration = "Configuration"
            case other = "Other"
            
            var icon: String {
                switch self {
                case .audio: return "waveform"
                case .measurement: return "chart.line.uptrend.xyaxis"
                case .configuration: return "gear"
                case .other: return "doc"
                }
            }
            
            var color: Color {
                switch self {
                case .audio: return .blue
                case .measurement: return .green
                case .configuration: return .orange
                case .other: return .secondary
                }
            }
        }
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        
        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: dateCreated)
        }
    }
    
    // MARK: - Public Methods
    
    func validatePaths(_ measurementDir: String) {
        guard !measurementDir.isEmpty else {
            resetState()
            return
        }
        
        isValidating = true
        
        Task {
            await performValidation(measurementDir)
        }
    }
    
    func updateLatestRecording(_ measurementDir: String) {
        guard !measurementDir.isEmpty else {
            latestRecording = ""
            recordingName = ""
            return
        }
        
        let dir = URL(fileURLWithPath: measurementDir)
        
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            if let latest = urls.max(by: { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return date1 < date2
            }) {
                latestRecording = latest.lastPathComponent
                
                if recordingName.isEmpty || recordingName == latestRecording {
                    recordingName = latestRecording
                }
            } else {
                latestRecording = ""
                recordingName = ""
            }
        } catch {
            latestRecording = ""
            recordingName = ""
            setError("Failed to scan directory: \(error.localizedDescription)")
        }
    }
    
    func saveLatest(from measurementDir: String, to path: String, log: @escaping (String) -> Void) {
        guard !latestRecording.isEmpty else {
            log("No recording to save\n")
            return
        }
        
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent(latestRecording).path
        saveFiles(files: [file], measurementDir: measurementDir, destination: path, log: log)
    }
    
    func saveFiles(files: [String], measurementDir: String, destination: String, log: @escaping (String) -> Void) {
        guard !files.isEmpty else {
            log("No files selected to save\n")
            return
        }
        
        Task {
            await performSaveOperation(files: files, measurementDir: measurementDir, destination: destination, log: log)
        }
    }
    
    func saveSelectedFiles(_ selectedFiles: [RecordingFile], to destination: String, log: @escaping (String) -> Void) {
        let filePaths = selectedFiles.map { $0.path }
        let measurementDir = URL(fileURLWithPath: selectedFiles.first?.path ?? "").deletingLastPathComponent().path
        
        saveFiles(files: filePaths, measurementDir: measurementDir, destination: destination, log: log)
    }
    
    func deleteFiles(_ filesToDelete: [RecordingFile], log: @escaping (String) -> Void) {
        Task {
            await performDeleteOperation(files: filesToDelete, log: log)
        }
    }
    
    func refreshRecordings(in measurementDir: String) {
        validatePaths(measurementDir)
    }
    
    // MARK: - Private Methods
    
    private func resetState() {
        measurementHasFiles = false
        latestRecording = ""
        recordingName = ""
        recordingFiles = []
        totalFileSize = 0
        recordingCount = 0
        isValidating = false
    }
    
    private func performValidation(_ measurementDir: String) async {
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: measurementDir)
            let visibleItems = items.filter { !$0.hasPrefix(".") }
            
            await MainActor.run {
                measurementHasFiles = !visibleItems.isEmpty
                recordingCount = visibleItems.count
            }
            
            await updateLatestRecording(measurementDir)
            await loadRecordingFiles(measurementDir)
            
        } catch {
            await MainActor.run {
                measurementHasFiles = false
                recordingFiles = []
                totalFileSize = 0
                recordingCount = 0
                setError("Failed to validate directory: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            isValidating = false
        }
    }
    
    private func updateLatestRecording(_ measurementDir: String) async {
        let dir = URL(fileURLWithPath: measurementDir)
        
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            if let latest = urls.max(by: { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return date1 < date2
            }) {
                await MainActor.run {
                    latestRecording = latest.lastPathComponent
                    
                    if recordingName.isEmpty || recordingName == latestRecording {
                        recordingName = latestRecording
                    }
                }
            } else {
                await MainActor.run {
                    latestRecording = ""
                    recordingName = ""
                }
            }
        } catch {
            await MainActor.run {
                latestRecording = ""
                recordingName = ""
                setError("Failed to scan directory: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadRecordingFiles(_ measurementDir: String) async {
        let dir = URL(fileURLWithPath: measurementDir)
        
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            var files: [RecordingFile] = []
            var totalSize: Int64 = 0
            
            for url in urls {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(resourceValues.fileSize ?? 0)
                let date = resourceValues.contentModificationDate ?? Date()
                
                let file = RecordingFile(
                    name: url.lastPathComponent,
                    path: url.path,
                    size: size,
                    dateCreated: date,
                    fileType: determineFileType(for: url)
                )
                
                files.append(file)
                totalSize += size
            }
            
            // Sort by date (newest first)
            files.sort { $0.dateCreated > $1.dateCreated }
            
            await MainActor.run {
                recordingFiles = files
                totalFileSize = totalSize
            }
            
        } catch {
            await MainActor.run {
                recordingFiles = []
                totalFileSize = 0
                setError("Failed to load recording files: \(error.localizedDescription)")
            }
        }
    }
    
    private func determineFileType(for url: URL) -> RecordingFile.FileType {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "wav", "mp3", "aiff", "flac", "m4a":
            return .audio
        case "json":
            return .configuration
        case "txt", "log", "csv":
            return .measurement
        default:
            return .other
        }
    }
    
    private func performSaveOperation(files: [String], measurementDir: String, destination: String, log: @escaping (String) -> Void) async {
        do {
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            
            let finalName = await MainActor.run {
                var name = recordingName.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty {
                    name = latestRecording
                }
                return name
            }
            
            var finalFileName = finalName
            var numbered = false
            
            if finalName == latestRecording {
                let base = URL(fileURLWithPath: finalName).deletingPathExtension().lastPathComponent
                let ext = URL(fileURLWithPath: finalName).pathExtension
                var candidate = finalName
                var idx = 1
                
                while FileManager.default.fileExists(atPath: URL(fileURLWithPath: destination).appendingPathComponent(candidate).path) {
                    candidate = "\(base)-\(idx).\(ext)"
                    idx += 1
                }
                finalFileName = candidate
                numbered = idx > 1
            }
            
            var savedCount = 0
            for src in files {
                var name = URL(fileURLWithPath: src).lastPathComponent
                if name == latestRecording {
                    name = finalFileName
                }
                let dst = URL(fileURLWithPath: destination).appendingPathComponent(name).path
                try FileManager.default.copyItem(atPath: src, toPath: dst)
                savedCount += 1
            }
            
            let message = "Saved \(savedCount) file(s) as \(finalFileName)\(numbered ? " with automatic numbering" : "")\n"
            log(message)
            
        } catch {
            await MainActor.run {
                setError("Failed to save files: \(error.localizedDescription)")
            }
            log("Failed to save measurement: \(error)\n")
        }
    }
    
    private func performDeleteOperation(files: [RecordingFile], log: @escaping (String) -> Void) async {
        var deletedCount = 0
        var errors: [String] = []
        
        for file in files {
            do {
                try FileManager.default.removeItem(atPath: file.path)
                deletedCount += 1
            } catch {
                errors.append("Failed to delete \(file.name): \(error.localizedDescription)")
            }
        }
        
        let message = "Deleted \(deletedCount) file(s)\n"
        log(message)
        
        if !errors.isEmpty {
            let errorMessage = errors.joined(separator: "\n")
            await MainActor.run {
                setError(errorMessage)
            }
            log("Errors occurred during deletion:\n\(errorMessage)\n")
        }
        
        // Refresh the directory after deletion
        if let firstFile = files.first {
            let measurementDir = URL(fileURLWithPath: firstFile.path).deletingLastPathComponent().path
            await performValidation(measurementDir)
        }
    }
    
    private func setError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
    
    // MARK: - Computed Properties
    
    var hasRecordings: Bool {
        !recordingFiles.isEmpty
    }
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }
    
    var recordingSummary: String {
        if recordingCount == 0 {
            return "No recordings"
        } else if recordingCount == 1 {
            return "1 recording (\(formattedTotalSize))"
        } else {
            return "\(recordingCount) recordings (\(formattedTotalSize))"
        }
    }
    
    var audioFiles: [RecordingFile] {
        recordingFiles.filter { $0.fileType == .audio }
    }
    
    var configurationFiles: [RecordingFile] {
        recordingFiles.filter { $0.fileType == .configuration }
    }
    
    var measurementFiles: [RecordingFile] {
        recordingFiles.filter { $0.fileType == .measurement }
    }
}

#else
// Fallback for non-SwiftUI environments
final class ModernRecordingViewModel {
    var measurementHasFiles: Bool = false
    var latestRecording: String = ""
    var recordingName: String = ""
    var showErrorAlert: Bool = false
    var errorMessage: String = ""
    var recordingFiles: [Any] = []
    var totalFileSize: Int64 = 0
    var recordingCount: Int = 0
    var isValidating: Bool = false
    
    func validatePaths(_ measurementDir: String) {}
    func updateLatestRecording(_ measurementDir: String) {}
    func saveLatest(from measurementDir: String, to path: String, log: @escaping (String) -> Void) {}
    func saveFiles(files: [String], measurementDir: String, destination: String, log: @escaping (String) -> Void) {}
    func refreshRecordings(in measurementDir: String) {}
}
#endif
