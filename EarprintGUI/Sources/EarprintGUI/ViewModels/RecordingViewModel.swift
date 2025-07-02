#if canImport(SwiftUI)
import SwiftUI
import Foundation

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var measurementHasFiles: Bool = false
    @Published var latestRecording: String = ""
    @Published var recordingName: String = ""
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""

    func validatePaths(_ measurementDir: String) {
        if let items = try? FileManager.default.contentsOfDirectory(atPath: measurementDir) {
            measurementHasFiles = items.contains { !$0.hasPrefix(".") }
        } else {
            measurementHasFiles = false
        }
        updateLatestRecording(measurementDir)
    }

    func updateLatestRecording(_ measurementDir: String) {
        let dir = URL(fileURLWithPath: measurementDir)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else {
            latestRecording = ""
            recordingName = ""
            return
        }
        if let latest = urls.max(by: {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast <
            (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }) {
            latestRecording = latest.lastPathComponent
        } else {
            latestRecording = ""
        }
        if recordingName.isEmpty || recordingName == latestRecording {
            recordingName = latestRecording
        }
    }

    func saveLatest(from measurementDir: String, to path: String, log: (String) -> Void) {
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent(latestRecording).path
        saveFiles(files: [file], measurementDir: measurementDir, destination: path, log: log)
    }

    func saveFiles(files: [String], measurementDir: String, destination: String, log: (String) -> Void) {
        guard !files.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            var finalName = recordingName.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalName.isEmpty { finalName = latestRecording }
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
                finalName = candidate
                numbered = idx > 1
            }
            for src in files {
                var name = URL(fileURLWithPath: src).lastPathComponent
                if name == latestRecording { name = finalName }
                let dst = URL(fileURLWithPath: destination).appendingPathComponent(name).path
                try FileManager.default.copyItem(atPath: src, toPath: dst)
            }
            log("Saved \(finalName)\(numbered ? " with automatic numbering" : "")\n")
        } catch {
            log("Failed to save measurement: \(error)\n")
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}
#endif