#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct ProfileView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    @Binding var measurementDir: String
    @Binding var headphoneFile: String
    @Binding var playbackDevice: String
    @State private var profiles: [String] = []
    @State private var selected: String?

    var body: some View {
        VStack {
            HStack {
                Button("Refresh") { loadProfiles() }
                Button("Load") { if let s = selected { loadProfile(name: s) } }
                Button("Save") { if let s = selected { saveProfile(name: s) } }
                Button("Delete") { if let s = selected { deleteProfile(name: s) } }
                Button("Import…") { importProfile() }
            }
            List(profiles, id: \.self, selection: $selected) { Text($0) }
        }
        .onAppear { loadProfiles() }
        .padding()
    }

    func loadProfiles() {
        let dir = URL(fileURLWithPath: measurementDir).appendingPathComponent("profiles")
        if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            profiles = items.filter { $0.pathExtension == "json" }.map { $0.lastPathComponent }
        }
    }

    func loadProfile(name: String) {
        let dir = URL(fileURLWithPath: measurementDir).appendingPathComponent("profiles")
        let file = dir.appendingPathComponent(name)
        guard
            let data = try? Data(contentsOf: file),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let brir = dict["brir_dir"] as? String { measurementDir = brir }
        if let eq = dict["headphone_file"] as? String { headphoneFile = eq }
        if let device = dict["playback_device"] as? String { playbackDevice = device }
        viewModel.log += "Loaded profile \(name)\n"
    }

    func saveProfile(name: String) {
        let dir = URL(fileURLWithPath: measurementDir).appendingPathComponent("profiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        let dict: [String: Any] = [
            "brir_dir": measurementDir,
            "headphone_file": headphoneFile,
            "playback_device": playbackDevice,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: file)
        }
        loadProfiles()
    }

    func deleteProfile(name: String) {
        let file = URL(fileURLWithPath: measurementDir).appendingPathComponent("profiles").appendingPathComponent(name)
        try? FileManager.default.removeItem(at: file)
        loadProfiles()
    }

    func importProfile() {
        let dir = URL(fileURLWithPath: measurementDir).appendingPathComponent("profiles")
        if let path = openPanel(directory: false, startPath: dir.path) {
            let url = URL(fileURLWithPath: path)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)
            loadProfiles()
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