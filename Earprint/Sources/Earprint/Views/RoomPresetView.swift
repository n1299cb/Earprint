#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct RoomPresetView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    @Binding var measurementDir: String
    @State private var presets: [String] = []
    @State private var selected: String?
    @State private var notes: String = ""

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
            TextEditor(text: $notes)
                .frame(height: 60)
        }
        .onAppear { loadPresets() }
        .padding()
    }

    func presetFile() -> URL {
        if let env = ProcessInfo.processInfo.environment["EARPRINT_ROOM_PRESETS"] {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("room_presets.json")
    }

    func loadPresets() {
        let url = presetFile()
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            presets = []
            return
        }
        presets = dict.keys.sorted()
    }

    func loadPreset(name: String) {
        let url = presetFile()
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
              let preset = dict[name] else { return }
        if let dir = preset["measurement_dir"] as? String { measurementDir = dir }
        if let note = preset["notes"] as? String { notes = note }
    }

    func savePreset(name: String) {
        let url = presetFile()
        var dict: [String: [String: Any]] = [:]
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            dict = loaded
        }
        dict[name] = [
            "brir_dir": measurementDir,
            "measurement_dir": measurementDir,
            "notes": notes,
            "measurement_date": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
        loadPresets()
    }

    func deletePreset(name: String) {
        let url = presetFile()
        guard var dict = (try? Data(contentsOf: url)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]] }) else {
            return
        }
        dict.removeValue(forKey: name)
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
        loadPresets()
    }

    func importPreset() {
        if let path = openPanel(directory: false, startPath: FileManager.default.currentDirectoryPath) {
            let url = URL(fileURLWithPath: path)
            let dest = presetFile()
            if let data = try? Data(contentsOf: url),
               var preset = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var dict: [String: [String: Any]] = [:]
                if let d = try? Data(contentsOf: dest),
                   let loaded = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] {
                    dict = loaded
                }
                let name = (preset["name"] as? String) ?? url.deletingPathExtension().lastPathComponent
                preset.removeValue(forKey: "name")
                dict[name] = preset
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
                    try? data.write(to: dest)
                }
                loadPresets()
            }
        }
    }

    // openPanel helper is provided by Utilities.swift
}
#endif
