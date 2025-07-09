#if canImport(SwiftUI)
import SwiftUI
import Foundation

// MARK: - Configuration Models
struct AppConfiguration: Codable, Equatable {
    var defaultMeasurementDir: String
    var defaultTestSignal: String
    var autoSaveResults: Bool
    var logLevel: LogLevel
    var pythonPath: String?
    var recentProjects: [String]
    var maxRecentProjects: Int
    
    static let `default` = AppConfiguration(
        defaultMeasurementDir: "",
        defaultTestSignal: "",
        autoSaveResults: true,
        logLevel: .info,
        pythonPath: nil,
        recentProjects: [],
        maxRecentProjects: 10
    )
}

struct ProcessingPreset: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var description: String
    var configurationData: Data // Store as Data instead of ProcessingConfiguration
    var createdDate: Date
    var modifiedDate: Date
    
    init(name: String, description: String, configurationData: Data) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.configurationData = configurationData
        self.createdDate = Date()
        self.modifiedDate = Date()
    }
    
    mutating func updateModifiedDate() {
        modifiedDate = Date()
    }
    
    static func == (lhs: ProcessingPreset, rhs: ProcessingPreset) -> Bool {
        lhs.id == rhs.id
    }
}

struct LayoutPreset: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var speakerLayout: [String]
    var channelMapping: [String: [Int]]
    var description: String
    var createdDate: Date
    
    init(name: String, speakerLayout: [String], channelMapping: [String: [Int]], description: String) {
        self.id = UUID().uuidString
        self.name = name
        self.speakerLayout = speakerLayout
        self.channelMapping = channelMapping
        self.description = description
        self.createdDate = Date()
    }
    
    static func == (lhs: LayoutPreset, rhs: LayoutPreset) -> Bool {
        lhs.id == rhs.id
    }
}

enum LogLevel: String, CaseIterable, Codable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}

enum ConfigurationError: LocalizedError {
    case invalidPath(String)
    case saveFailure(String)
    case loadFailure(String)
    case validationFailure(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .saveFailure(let reason):
            return "Failed to save configuration: \(reason)"
        case .loadFailure(let reason):
            return "Failed to load configuration: \(reason)"
        case .validationFailure(let reason):
            return "Configuration validation failed: \(reason)"
        }
    }
}

// MARK: - Configuration ViewModel
@MainActor
final class ConfigurationViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var appConfiguration: AppConfiguration = .default
    @Published var processingPresets: [ProcessingPreset] = []
    @Published var layoutPresets: [LayoutPreset] = []
    @Published var selectedProcessingPreset: ProcessingPreset?
    @Published var selectedLayoutPreset: LayoutPreset?
    @Published var isDirty: Bool = false
    @Published var lastError: ConfigurationError?
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    
    // MARK: - Private Properties
    private let configurationURL: URL
    private let presetsURL: URL
    private let layoutsURL: URL
    
    init() {
        // Setup configuration file URLs
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Earprint")
        
        configurationURL = appFolder.appendingPathComponent("configuration.json")
        presetsURL = appFolder.appendingPathComponent("processing_presets.json")
        layoutsURL = appFolder.appendingPathComponent("layout_presets.json")
        
        // Create directories if needed
        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        loadConfiguration()
    }
    
    // MARK: - Configuration Management
    func loadConfiguration() {
        isLoading = true
        
        Task {
            let config = await loadAppConfiguration()
            let presets = await loadProcessingPresets()
            let layouts = await loadLayoutPresets()
            
            self.appConfiguration = config
            self.processingPresets = presets
            self.layoutPresets = layouts
            self.isDirty = false
            self.lastError = nil
            self.isLoading = false
        }
    }
    
    func saveConfiguration() {
        guard !isSaving else { return }
        isSaving = true
        
        Task {
            do {
                try await saveAppConfiguration()
                try await saveProcessingPresets()
                try await saveLayoutPresets()
                
                self.isDirty = false
                self.lastError = nil
            } catch {
                self.lastError = error as? ConfigurationError ?? .saveFailure(error.localizedDescription)
            }
            
            self.isSaving = false
        }
    }
    
    func resetToDefaults() {
        appConfiguration = .default
        processingPresets = []
        layoutPresets = []
        selectedProcessingPreset = nil
        selectedLayoutPreset = nil
        isDirty = true
    }
    
    // MARK: - App Configuration
    func updateDefaultMeasurementDir(_ path: String) {
        guard validatePath(path) else {
            lastError = .invalidPath(path)
            return
        }
        appConfiguration.defaultMeasurementDir = path
        isDirty = true
    }
    
    func updateDefaultTestSignal(_ path: String) {
        guard validatePath(path) else {
            lastError = .invalidPath(path)
            return
        }
        appConfiguration.defaultTestSignal = path
        isDirty = true
    }
    
    func updateLogLevel(_ level: LogLevel) {
        appConfiguration.logLevel = level
        isDirty = true
    }
    
    func updateAutoSaveResults(_ enabled: Bool) {
        appConfiguration.autoSaveResults = enabled
        isDirty = true
    }
    
    func updatePythonPath(_ path: String?) {
        appConfiguration.pythonPath = path
        isDirty = true
    }
    
    func addRecentProject(_ path: String) {
        guard validatePath(path) else { return }
        
        // Remove if already exists
        appConfiguration.recentProjects.removeAll { $0 == path }
        
        // Add to beginning
        appConfiguration.recentProjects.insert(path, at: 0)
        
        // Limit to max count
        if appConfiguration.recentProjects.count > appConfiguration.maxRecentProjects {
            appConfiguration.recentProjects = Array(appConfiguration.recentProjects.prefix(appConfiguration.maxRecentProjects))
        }
        
        isDirty = true
    }
    
    func removeRecentProject(_ path: String) {
        appConfiguration.recentProjects.removeAll { $0 == path }
        isDirty = true
    }
    
    func clearRecentProjects() {
        appConfiguration.recentProjects.removeAll()
        isDirty = true
    }
    
    // MARK: - Processing Presets
    func createProcessingPreset(name: String, description: String, configurationData: Data) {
        let preset = ProcessingPreset(
            name: name,
            description: description,
            configurationData: configurationData
        )
        
        processingPresets.append(preset)
        processingPresets.sort { $0.name < $1.name }
        isDirty = true
    }
    
    func updateProcessingPreset(_ presetId: String, configurationData: Data) {
        guard let index = processingPresets.firstIndex(where: { $0.id == presetId }) else { return }
        
        processingPresets[index].configurationData = configurationData
        processingPresets[index].updateModifiedDate()
        isDirty = true
    }
    
    func deleteProcessingPreset(_ preset: ProcessingPreset) {
        processingPresets.removeAll { $0.id == preset.id }
        
        if selectedProcessingPreset?.id == preset.id {
            selectedProcessingPreset = nil
        }
        
        isDirty = true
    }
    
    func duplicateProcessingPreset(_ preset: ProcessingPreset) {
        let duplicate = ProcessingPreset(
            name: "\(preset.name) Copy",
            description: preset.description,
            configurationData: preset.configurationData
        )
        
        processingPresets.append(duplicate)
        processingPresets.sort { $0.name < $1.name }
        isDirty = true
    }
    
    func renameProcessingPreset(_ preset: ProcessingPreset, newName: String) {
        guard let index = processingPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        
        processingPresets[index].name = newName
        processingPresets[index].updateModifiedDate()
        processingPresets.sort { $0.name < $1.name }
        isDirty = true
    }
    
    // MARK: - Layout Presets
    func createLayoutPreset(name: String, speakerLayout: [String], channelMapping: [String: [Int]], description: String) {
        let preset = LayoutPreset(
            name: name,
            speakerLayout: speakerLayout,
            channelMapping: channelMapping,
            description: description
        )
        
        layoutPresets.append(preset)
        layoutPresets.sort { $0.name < $1.name }
        isDirty = true
    }
    
    func deleteLayoutPreset(_ preset: LayoutPreset) {
        layoutPresets.removeAll { $0.id == preset.id }
        
        if selectedLayoutPreset?.id == preset.id {
            selectedLayoutPreset = nil
        }
        
        isDirty = true
    }
    
    func duplicateLayoutPreset(_ preset: LayoutPreset) {
        let duplicate = LayoutPreset(
            name: "\(preset.name) Copy",
            speakerLayout: preset.speakerLayout,
            channelMapping: preset.channelMapping,
            description: preset.description
        )
        
        layoutPresets.append(duplicate)
        layoutPresets.sort { $0.name < $1.name }
        isDirty = true
    }
    
    func renameLayoutPreset(_ preset: LayoutPreset, newName: String) {
        guard let index = layoutPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        
        layoutPresets[index].name = newName
        isDirty = true
    }
    
    // MARK: - Import/Export
    func exportConfiguration(to url: URL) async throws {
        let exportData = ConfigurationExport(
            appConfiguration: appConfiguration,
            processingPresets: processingPresets,
            layoutPresets: layoutPresets,
            exportDate: Date(),
            version: "1.0"
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(exportData)
        try data.write(to: url)
    }
    
    func importConfiguration(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let importData = try decoder.decode(ConfigurationExport.self, from: data)
        
        // Merge configuration
        self.appConfiguration = importData.appConfiguration
        self.processingPresets = importData.processingPresets
        self.layoutPresets = importData.layoutPresets
        self.isDirty = true
    }
    
    func exportPreset(_ preset: ProcessingPreset, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(preset)
        try data.write(to: url)
    }
    
    func importPreset(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let preset = try decoder.decode(ProcessingPreset.self, from: data)
        
        // Ensure unique name
        var importedPreset = preset
        var counter = 1
        let baseName = preset.name
        
        while processingPresets.contains(where: { $0.name == importedPreset.name }) {
            importedPreset.name = "\(baseName) (\(counter))"
            counter += 1
        }
        
        self.processingPresets.append(importedPreset)
        self.processingPresets.sort { $0.name < $1.name }
        self.isDirty = true
    }
    
    // MARK: - Validation
    func validateConfiguration() -> [String] {
        var issues: [String] = []
        
        if !appConfiguration.defaultMeasurementDir.isEmpty && !validatePath(appConfiguration.defaultMeasurementDir) {
            issues.append("Invalid default measurement directory")
        }
        
        if !appConfiguration.defaultTestSignal.isEmpty && !validatePath(appConfiguration.defaultTestSignal) {
            issues.append("Invalid default test signal file")
        }
        
        if let pythonPath = appConfiguration.pythonPath, !validatePath(pythonPath) {
            issues.append("Invalid Python path")
        }
        
        // Validate recent projects
        let invalidProjects = appConfiguration.recentProjects.filter { !validatePath($0) }
        if !invalidProjects.isEmpty {
            issues.append("Some recent projects point to invalid paths")
        }
        
        return issues
    }
    
    func cleanupConfiguration() {
        // Remove invalid recent projects
        appConfiguration.recentProjects = appConfiguration.recentProjects.filter { validatePath($0) }
        
        // Remove duplicate presets
        var seenProcessingNames = Set<String>()
        processingPresets = processingPresets.filter { preset in
            let isUnique = !seenProcessingNames.contains(preset.name)
            seenProcessingNames.insert(preset.name)
            return isUnique
        }
        
        var seenLayoutNames = Set<String>()
        layoutPresets = layoutPresets.filter { preset in
            let isUnique = !seenLayoutNames.contains(preset.name)
            seenLayoutNames.insert(preset.name)
            return isUnique
        }
        
        isDirty = true
    }
    
    // MARK: - Private Methods
    private func validatePath(_ path: String) -> Bool {
        guard !path.isEmpty else { return true } // Empty paths are valid (use defaults)
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func loadAppConfiguration() async -> AppConfiguration {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fileManager = FileManager.default
                do {
                    guard fileManager.fileExists(atPath: self.configurationURL.path) else {
                        continuation.resume(returning: .default)
                        return
                    }
                    
                    let data = try Data(contentsOf: self.configurationURL)
                    let decoder = JSONDecoder()
                    let config = try decoder.decode(AppConfiguration.self, from: data)
                    continuation.resume(returning: config)
                } catch {
                    continuation.resume(returning: .default)
                }
            }
        }
    }
    
    private func saveAppConfiguration() async throws {
        let configToSave = appConfiguration // Capture on main actor
        
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(configToSave)
                    try data.write(to: self.configurationURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func loadProcessingPresets() async -> [ProcessingPreset] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fileManager = FileManager.default
                do {
                    guard fileManager.fileExists(atPath: self.presetsURL.path) else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    let data = try Data(contentsOf: self.presetsURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let presets = try decoder.decode([ProcessingPreset].self, from: data)
                    continuation.resume(returning: presets)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func saveProcessingPresets() async throws {
        let presetsToSave = processingPresets // Capture on main actor
        
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(presetsToSave)
                    try data.write(to: self.presetsURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func loadLayoutPresets() async -> [LayoutPreset] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fileManager = FileManager.default
                do {
                    guard fileManager.fileExists(atPath: self.layoutsURL.path) else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    let data = try Data(contentsOf: self.layoutsURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let layouts = try decoder.decode([LayoutPreset].self, from: data)
                    continuation.resume(returning: layouts)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func saveLayoutPresets() async throws {
        let layoutsToSave = layoutPresets // Capture on main actor
        
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(layoutsToSave)
                    try data.write(to: self.layoutsURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Export/Import Models
struct ConfigurationExport: Codable {
    let appConfiguration: AppConfiguration
    let processingPresets: [ProcessingPreset]
    let layoutPresets: [LayoutPreset]
    let exportDate: Date
    let version: String
}

// MARK: - Configuration Extensions
extension AppConfiguration {
    var isValid: Bool {
        guard !defaultMeasurementDir.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: defaultMeasurementDir)
    }
    
    var hasValidTestSignal: Bool {
        guard !defaultTestSignal.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: defaultTestSignal)
    }
}

extension ProcessingPreset {
    var isComplete: Bool {
        !configurationData.isEmpty
    }
    
    var configurationSummary: String {
        // Since we're storing as Data, provide a generic summary
        let size = ByteCountFormatter.string(fromByteCount: Int64(configurationData.count), countStyle: .file)
        return "Configuration: \(size)"
    }
}

extension LayoutPreset {
    var channelCount: Int {
        speakerLayout.count
    }
    
    var layoutSummary: String {
        "\(channelCount) channels: \(speakerLayout.prefix(3).joined(separator: ", "))\(speakerLayout.count > 3 ? "..." : "")"
    }
}

#else
// Non-macOS stub implementation
final class ConfigurationViewModel: ObservableObject {
    @Published var appConfiguration: AppConfiguration = .default
    @Published var processingPresets: [ProcessingPreset] = []
    @Published var layoutPresets: [LayoutPreset] = []
    @Published var selectedProcessingPreset: ProcessingPreset? = nil
    @Published var selectedLayoutPreset: LayoutPreset? = nil
    @Published var isDirty: Bool = false
    @Published var lastError: ConfigurationError? = nil
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    
    func loadConfiguration() {}
    func saveConfiguration() {}
    func resetToDefaults() {}
    func updateDefaultMeasurementDir(_ path: String) {}
    func updateDefaultTestSignal(_ path: String) {}
    func updateLogLevel(_ level: LogLevel) {}
    func updateAutoSaveResults(_ enabled: Bool) {}
    func updatePythonPath(_ path: String?) {}
    func addRecentProject(_ path: String) {}
    func removeRecentProject(_ path: String) {}
    func clearRecentProjects() {}
    func createProcessingPreset(name: String, description: String, configurationData: Data) {}
    func updateProcessingPreset(_ presetId: String, configurationData: Data) {}
    func deleteProcessingPreset(_ preset: ProcessingPreset) {}
    func duplicateProcessingPreset(_ preset: ProcessingPreset) {}
    func renameProcessingPreset(_ preset: ProcessingPreset, newName: String) {}
    func createLayoutPreset(name: String, speakerLayout: [String], channelMapping: [String: [Int]], description: String) {}
    func deleteLayoutPreset(_ preset: LayoutPreset) {}
    func duplicateLayoutPreset(_ preset: LayoutPreset) {}
    func renameLayoutPreset(_ preset: LayoutPreset, newName: String) {}
    func exportConfiguration(to url: URL) async throws {}
    func importConfiguration(from url: URL) async throws {}
    func exportPreset(_ preset: ProcessingPreset, to url: URL) async throws {}
    func importPreset(from url: URL) async throws {}
    func validateConfiguration() -> [String] { return [] }
    func cleanupConfiguration() {}
}
#endif
