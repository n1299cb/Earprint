import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Root directory of the repository.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Utilities.swift
    .deletingLastPathComponent() // EarprintGUI
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // EarprintGUI package
/// Directory containing bundled scripts.
let scriptsRoot = Bundle.module.resourceURL ?? repoRoot

/// URL to the bundled Python interpreter if present.
let embeddedPythonURL: URL? = Bundle.module
    .url(forResource: "Python", withExtension: "framework", subdirectory: "EmbeddedPython")?
    .appendingPathComponent("Versions")
    .appendingPathComponent("Current")
    .appendingPathComponent("bin/python3")

/// Returns the path to an included script, searching multiple locations.
func scriptPath(_ name: String, scriptsRoot: URL = scriptsRoot, repoRoot: URL = repoRoot) -> String {
    let fm = FileManager.default
    if let path = Bundle.module.path(forResource: name, ofType: nil) {
        return path
    }
    let direct = scriptsRoot.appendingPathComponent(name).path
    if fm.fileExists(atPath: direct) { return direct }
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    let parent = cwd.deletingLastPathComponent().appendingPathComponent(name).path
    if fm.fileExists(atPath: parent) { return parent }
    let repo = repoRoot.appendingPathComponent(name).path
    if fm.fileExists(atPath: repo) { return repo }
    return name
}

#if canImport(AppKit)
/// Present an NSOpenPanel configured for files or directories.
@MainActor
func openPanel(directory: Bool, startPath: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = !directory
    panel.canChooseDirectories = directory
    panel.allowsMultipleSelection = false
    if !startPath.isEmpty {
        let base = directory ? startPath : (startPath as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue {
            panel.directoryURL = URL(fileURLWithPath: base)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
    }
    return panel.runModal() == .OK ? panel.url?.path : nil
}
#endif
