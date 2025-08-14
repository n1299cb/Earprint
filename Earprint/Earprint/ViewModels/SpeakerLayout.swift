import Foundation
import SwiftUI

// MARK: - Speaker Layout Models
struct SpeakerLayout: Codable, Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let groups: [SpeakerGroup]
    let icon: String
    
    var totalSpeakers: Int {
        groups.flatMap(\.speakers).count
    }
    
    var speakerLabels: [String] {
        groups.flatMap(\.speakers)
    }
    
    private enum CodingKeys: String, CodingKey {
        case name, displayName, groups, icon
    }
}

struct SpeakerGroup: Codable, Identifiable {
    let id = UUID()
    let name: String
    let speakers: [String]
    
    private enum CodingKeys: String, CodingKey {
        case name, speakers
    }
}

// MARK: - Layout Manager
@MainActor
final class LayoutManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var selectedLayoutName: String = "7.1" {
        didSet {
            if oldValue != selectedLayoutName {
                saveToUserDefaults()
                notifyLayoutChanged()
                validateCurrentLayout()
            }
        }
    }
    
    @Published var availableLayouts: [String: SpeakerLayout] = [:]
    @Published var isLoading: Bool = false
    @Published var layoutWarnings: [String] = []
    @Published var loadError: String?
    
    // MARK: - Singleton
    static let shared = LayoutManager()
    
    private init() {
        loadFromUserDefaults()
        Task {
            await loadLayoutsFromPython()
        }
    }
    
    // MARK: - Public Methods
    func updateLayout(_ layoutName: String) {
        guard availableLayouts.keys.contains(layoutName) else {
            print("⚠️ Layout '\(layoutName)' not found in available layouts")
            return
        }
        selectedLayoutName = layoutName
    }
    
    func getCurrentLayout() -> SpeakerLayout? {
        return availableLayouts[selectedLayoutName]
    }
    
    func getSpeakerLabels() -> [String] {
        return getCurrentLayout()?.speakerLabels ?? []
    }
    
    func getTotalChannelCount() -> Int {
        return getCurrentLayout()?.totalSpeakers ?? 0
    }
    
    func validateLayout(against deviceChannels: Int) -> [String] {
        var warnings: [String] = []
        
        guard let layout = getCurrentLayout() else {
            warnings.append("No layout selected")
            return warnings
        }
        
        let requiredChannels = layout.totalSpeakers
        if deviceChannels < requiredChannels {
            warnings.append("Layout '\(layout.displayName)' requires \(requiredChannels) channels but device only has \(deviceChannels)")
        }
        
        return warnings
    }
    
    func refreshLayouts() {
        isLoading = true
        loadError = nil
        
        Task {
            await loadLayoutsFromPython()
            
            // Validate current selection
            if !availableLayouts.keys.contains(selectedLayoutName) {
                // Fallback to first available layout
                selectedLayoutName = availableLayouts.keys.sorted().first ?? "2.0"
            }
            
            isLoading = false
        }
    }
    
    // MARK: - Python Integration
    private func loadLayoutsFromPython() async {
        do {
            let layouts = try await fetchLayoutsFromPython()
            await MainActor.run {
                self.availableLayouts = layouts
                self.loadError = nil
                self.validateCurrentLayout()
            }
        } catch {
            await MainActor.run {
                self.loadError = "Failed to load layouts: \(error.localizedDescription)"
                print("❌ Layout loading error: \(error)")
                
                // Fallback to minimal layouts if Python fails
                self.loadFallbackLayouts()
            }
        }
    }
    
    private func fetchLayoutsFromPython() async throws -> [String: SpeakerLayout] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let layouts = try self.executeLayoutScript()
                    continuation.resume(returning: layouts)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func executeLayoutScript() throws -> [String: SpeakerLayout] {
        let process = Process()
        
        // Try to find Python executable
        if let pythonPath = findPythonExecutable() {
            process.executableURL = URL(fileURLWithPath: pythonPath)
        } else {
            // Fallback to system python
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        }
        
        // Python script to extract layouts from constants.py
        process.arguments = [
            "-c",
            """
            import sys
            import json
            sys.path.append('\(Bundle.main.resourcePath ?? "")/Scripts')
            
            try:
                import constants
                
                def format_display_name(name):
                    if '.' in name:
                        parts = name.split('.')
                        if len(parts) == 2:
                            return f"{parts[0]}.{parts[1]}"
                        elif len(parts) == 3:
                            return f"{parts[0]}.{parts[1]}.{parts[2]}"
                    return name.upper()
                
                def get_icon_for_layout(name):
                    if 'ambisonics' in name.lower():
                        return 'globe'
                    elif '.4' in name or '.6' in name or '.2' in name:
                        return 'dot.radiowaves.up.forward'
                    elif name == '1.0':
                        return 'speaker'
                    elif name == '2.0':
                        return 'speaker.2'
                    elif name.startswith('5.'):
                        return 'speaker.wave.3'
                    elif name.startswith('7.'):
                        return 'hifispeaker.2'
                    elif name.startswith('9.'):
                        return 'hifispeaker.fill'
                    else:
                        return 'speaker.wave.3'
                
                layouts = {}
                for name, groups in constants.SPEAKER_LAYOUTS.items():
                    # Convert groups to proper format
                    layout_groups = []
                    for i, group in enumerate(groups):
                        group_name = f"Group {i+1}" if len(groups) > 1 else "Main"
                        # Special naming for common groups
                        if len(groups) > 1:
                            if i == 0:
                                group_name = "Main"
                            elif i == 1 and "FC" in group:
                                group_name = "Center"
                            elif "LFE" in group:
                                group_name = "LFE"
                            elif any(s.startswith("S") for s in group):
                                group_name = "Surround"
                            elif any(s.startswith("B") for s in group):
                                group_name = "Rear"
                            elif any(s.startswith("T") for s in group):
                                group_name = "Height"
                            elif any(s.startswith("W") for s in group):
                                group_name = "Wide"
                        
                        layout_groups.append({
                            'name': group_name,
                            'speakers': group
                        })
                    
                    layouts[name] = {
                        'name': name,
                        'displayName': format_display_name(name),
                        'groups': layout_groups,
                        'icon': get_icon_for_layout(name)
                    }
                
                print(json.dumps(layouts), flush=True)
                
            except Exception as e:
                print(f"Error: {e}", file=sys.stderr)
                sys.exit(1)
            """
        ]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if process.terminationStatus != 0 {
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw LayoutError.pythonScriptFailed(errorString)
            }
            
            if !errorData.isEmpty, let errorString = String(data: errorData, encoding: .utf8) {
                print("⚠️ Python stderr: \(errorString)")
            }
            
            guard let layoutsDict = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                throw LayoutError.invalidJSON("Failed to parse layout JSON")
            }
            
            return try parseLayoutsFromJSON(layoutsDict)
            
        } catch {
            throw LayoutError.executionFailed(error.localizedDescription)
        }
    }
    
    private func parseLayoutsFromJSON(_ layoutsDict: [String: [String: Any]]) throws -> [String: SpeakerLayout] {
        var layouts: [String: SpeakerLayout] = [:]
        
        for (name, layoutData) in layoutsDict {
            guard let displayName = layoutData["displayName"] as? String,
                  let icon = layoutData["icon"] as? String,
                  let groupsData = layoutData["groups"] as? [[String: Any]] else {
                continue
            }
            
            var groups: [SpeakerGroup] = []
            for groupData in groupsData {
                guard let groupName = groupData["name"] as? String,
                      let speakers = groupData["speakers"] as? [String] else {
                    continue
                }
                groups.append(SpeakerGroup(name: groupName, speakers: speakers))
            }
            
            layouts[name] = SpeakerLayout(
                name: name,
                displayName: displayName,
                groups: groups,
                icon: icon
            )
        }
        
        return layouts
    }
    
    private func findPythonExecutable() -> String? {
        // Check for bundled Python first
        let bundledPaths = [
            "\(Bundle.main.resourcePath ?? "")/EmbeddedPython/Python.framework/Versions/Current/bin/python3",
            "\(Bundle.main.resourcePath ?? "")/EmbeddedPython/bin/python3",
            "\(Bundle.main.bundlePath)/Contents/Resources/EmbeddedPython/bin/python3"
        ]
        
        for path in bundledPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Fallback to system Python
        let systemPaths = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    private func loadFallbackLayouts() {
        // Minimal fallback layouts if Python fails
        let fallbackLayouts: [SpeakerLayout] = [
            SpeakerLayout(
                name: "2.0",
                displayName: "2.0 Stereo",
                groups: [SpeakerGroup(name: "Main", speakers: ["FL", "FR"])],
                icon: "speaker.2"
            ),
            SpeakerLayout(
                name: "5.1",
                displayName: "5.1 Surround", 
                groups: [
                    SpeakerGroup(name: "Main", speakers: ["FL", "FR"]),
                    SpeakerGroup(name: "Center", speakers: ["FC"]),
                    SpeakerGroup(name: "LFE", speakers: ["LFE"]),
                    SpeakerGroup(name: "Surround", speakers: ["SL", "SR"])
                ],
                icon: "speaker.wave.3"
            )
        ]
        
        for layout in fallbackLayouts {
            availableLayouts[layout.name] = layout
        }
    }
    
    // MARK: - Private Methods
    private func validateCurrentLayout() {
        layoutWarnings.removeAll()
        
        guard let layout = getCurrentLayout() else {
            layoutWarnings.append("No valid layout selected")
            return
        }
        
        if layout.groups.isEmpty {
            layoutWarnings.append("Layout has no speaker groups")
        }
        
        if layout.totalSpeakers == 0 {
            layoutWarnings.append("Layout has no speakers defined")
        }
    }
    
    private func notifyLayoutChanged() {
        NotificationCenter.default.post(
            name: .layoutChanged,
            object: nil,
            userInfo: [
                "layoutName": selectedLayoutName,
                "layout": getCurrentLayout() as Any
            ]
        )
    }
    
    // MARK: - Persistence
    private var userDefaultsKey: String { "selectedSpeakerLayout" }
    
    private func loadFromUserDefaults() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey) {
            selectedLayoutName = saved
        }
    }
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(selectedLayoutName, forKey: userDefaultsKey)
    }
}

// MARK: - Error Types
enum LayoutError: LocalizedError {
    case pythonScriptFailed(String)
    case invalidJSON(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .pythonScriptFailed(let message):
            return "Python script failed: \(message)"
        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let layoutChanged = Notification.Name("speakerLayoutChanged")
}

// MARK: - Layout Manager Extensions
extension LayoutManager {
    
    /// Get speaker labels as an array for channel mapping
    func getSpeakerLabelsArray() -> [String] {
        return getCurrentLayout()?.speakerLabels ?? []
    }
    
    /// Check if a layout requires a specific number of channels
    func layoutRequiresChannels(_ channels: Int) -> Bool {
        return getTotalChannelCount() == channels
    }
    
    /// Get layout groups for recording sequence
    func getLayoutGroups() -> [SpeakerGroup] {
        return getCurrentLayout()?.groups ?? []
    }
    
    /// Get available layout names sorted
    var availableLayoutNames: [String] {
        return availableLayouts.keys.sorted()
    }
    
    /// Check if current layout is valid
    var isCurrentLayoutValid: Bool {
        return getCurrentLayout() != nil && layoutWarnings.isEmpty
    }
    
    /// Force reload layouts from Python
    func forceReloadLayouts() {
        Task {
            await loadLayoutsFromPython()
        }
    }
}
