#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct PresetView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    var measurementDir: String
    @State private var presets: [String] = []
    @State private var selected: String?

    var body: some View {
        VStack {
            HStack {
                Button("Refresh") { loadPresets() }
                Button("Load") { if let s = selected { loadPreset(name: s) } }
                Button("Save") { if let s = selected { savePreset(name: s) } }
                Button("Delete") { if let s = selected { deletePreset(name: s) } }
                Button("Import…") { importPreset() }
            }
            List(presets, id: \.self, selection: $selected) { Text($0) }
        }
        .onAppear { loadPresets() }
        .padding()
    }

    func loadPresets() {
        let dir = URL(fileURLWithPath: measurementDir).appendingPathComponent("presets")
        if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            presets = items.filter { $0.pathExtension == "json" }.map { $0.lastPathComponent }
        }
    }

    func loadPreset(name: String) {
        viewModel.log += "Loaded preset \(name)\n"
    }

    func savePreset(name: String) {
        let dir = URL(fileURLWithPath: measurementDir).appendingPathComponent("presets")
        let src = dir.appendingPathComponent(name)
        if let url = savePanel(start: dir.path, name: name) {
            try? FileManager.default.copyItem(at: src, to: url)
            loadPresets()
        }
    }

    func deletePreset(name: String) {
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent("presets").appendingPathComponent(name)
        try? FileManager.default.removeItem(at: file)
        loadPresets()
    }

    func importPreset() {
        let dir = URL(fileURLWithPath: measurementDir).appendingPathComponent("presets")
        if let path = openPanel(directory: false, startPath: dir.path) {
            let url = URL(fileURLWithPath: path)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)
            loadPresets()
        }
    }

    // openPanel helper is provided by Utilities.swift

    func savePanel(start: String, name: String) -> URL? {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.directoryURL = URL(fileURLWithPath: start)
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return nil
        #endif
    }
}
#endif