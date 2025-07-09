import SwiftUI

struct ChannelMappingView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Input parameters
    let playbackChannels: Int
    let recordingChannels: Int
    let speakerLabels: [String]
    let playbackDevice: String
    
    // Bindings
    @Binding var channelMapping: [String: [Int]]
    @Binding var isPresented: Bool
    
    // Callback
    var onSave: () -> Void = {}
    
    // State
    @State private var speakerSelections: [Int] = []
    @State private var micSelections: [Int] = []
    @State private var useTone: Bool = true
    @State private var isTestingChannel: Bool = false
    @State private var testingChannelIndex: Int? = nil
    
    // Computed properties
    private var mappingCompatible: Bool {
        playbackChannels >= speakerLabels.count && recordingChannels >= 2
    }
    
    private var channelWarning: String? {
        var warnings: [String] = []
        if playbackChannels < speakerLabels.count && !speakerLabels.isEmpty {
            warnings.append("Playback device only has \(playbackChannels) channels while layout requires \(speakerLabels.count).")
        }
        if recordingChannels < 2 {
            let suffix = recordingChannels == 1 ? "" : "s"
            warnings.append("Recording device only has \(recordingChannels) channel\(suffix); two are required.")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }
    
    init(playbackChannels: Int,
         recordingChannels: Int,
         speakerLabels: [String],
         playbackDevice: String,
         channelMapping: Binding<[String: [Int]]>,
         isPresented: Binding<Bool>,
         onSave: @escaping () -> Void = {}) {
        self.playbackChannels = playbackChannels
        self.recordingChannels = recordingChannels
        self.speakerLabels = speakerLabels
        self.playbackDevice = playbackDevice
        self._channelMapping = channelMapping
        self._isPresented = isPresented
        self.onSave = onSave
        
        // Initialize selections from existing mapping or defaults
        let outputChannels = channelMapping.wrappedValue["output_channels"] ?? Array(0..<speakerLabels.count)
        let inputChannels = channelMapping.wrappedValue["input_channels"] ?? [0, 1]
        
        _speakerSelections = State(initialValue: outputChannels)
        _micSelections = State(initialValue: inputChannels)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content - vertical stack instead of horizontal
            ScrollView {
                VStack(spacing: 20) {
                    // Speaker mapping section
                    speakerSection
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Microphone mapping section
                    microphoneSection
                }
                .padding(.vertical, 16)
            }
            
            Divider()
            
            // Footer with warnings and actions
            footerView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            initializeSelections()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Channel Mapping")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Assign audio device channels")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Test signal controls - inline
            HStack(spacing: 6) {
                Text("Test:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Test Signal", selection: $useTone) {
                    Text("Tone").tag(true)
                    Text("Noise").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Speaker Section
    private var speakerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "speaker.wave.3")
                    .foregroundColor(.accentColor)
                
                Text("Speaker Channels")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(playbackChannels) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            
            // Speaker assignments in a compact grid
            if speakerLabels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    Text("No speaker labels available")
                        .foregroundColor(.secondary)
                    
                    Text("Select a valid speaker layout in settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(Array(speakerLabels.enumerated()), id: \.offset) { index, label in
                        speakerRow(index: index, label: label)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func speakerRow(index: Int, label: String) -> some View {
        VStack(spacing: 6) {
            // Speaker label
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Test button
                Button(action: {
                    testChannel(index: index, isOutput: true)
                }) {
                    HStack(spacing: 2) {
                        if isTestingChannel && testingChannelIndex == index {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.caption2)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .disabled(isTestingChannel || index >= speakerSelections.count)
            }
            
            // Channel picker
            Picker("Channel", selection: Binding(
                get: {
                    index < speakerSelections.count ? speakerSelections[index] : 0
                },
                set: { newValue in
                    ensureSelectionsCapacity(index: index)
                    speakerSelections[index] = newValue
                }
            )) {
                ForEach(0..<playbackChannels, id: \.self) { channel in
                    Text("Ch \(channel + 1)").tag(channel)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Microphone Section
    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "mic")
                    .foregroundColor(.accentColor)
                
                Text("Microphone Channels")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(recordingChannels) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            
            // Microphone assignments in a horizontal layout
            HStack(spacing: 12) {
                let micLabels = ["Left Mic", "Right Mic"]
                
                ForEach(Array(micLabels.enumerated()), id: \.offset) { index, label in
                    microphoneRow(index: index, label: label)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func microphoneRow(index: Int, label: String) -> some View {
        VStack(spacing: 6) {
            // Microphone label
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Channel picker
            Picker("Channel", selection: Binding(
                get: {
                    index < micSelections.count ? micSelections[index] : index
                },
                set: { newValue in
                    while micSelections.count <= index {
                        micSelections.append(index)
                    }
                    micSelections[index] = newValue
                }
            )) {
                ForEach(0..<max(recordingChannels, 1), id: \.self) { channel in
                    Text("Ch \(channel + 1)").tag(channel)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Footer View
    private var footerView: some View {
        VStack(spacing: 12) {
            // Warnings
            if let warning = channelWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Debug Bundle") {
                    debugBundleStructure()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Cancel") {
                    isPresented = false
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Auto Map") {
                    autoMapChannels()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveMapping()
                }
                .buttonStyle(.borderedProminent)
                .disabled(channelWarning != nil)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Helper Methods
    private func debugBundleStructure() {
        print("🔍 === BUNDLE DEBUG ===")
        print("🔍 Bundle.main.resourceURL: \(Bundle.main.resourceURL?.path ?? "nil")")
        print("🔍 Bundle.main.bundleURL: \(Bundle.main.bundleURL.path)")
        
        // Check if EmbeddedPython directory exists
        if let resourceURL = Bundle.main.resourceURL {
            let embeddedDir = resourceURL.appendingPathComponent("EmbeddedPython")
            print("🔍 EmbeddedPython directory path: \(embeddedDir.path)")
            print("🔍 EmbeddedPython exists: \(FileManager.default.fileExists(atPath: embeddedDir.path))")
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: embeddedDir, includingPropertiesForKeys: nil)
                print("🔍 EmbeddedPython contents:")
                for item in contents {
                    print("   - \(item.lastPathComponent)")
                    if item.lastPathComponent == "Python.framework" {
                        let versionsDir = item.appendingPathComponent("Versions")
                        if FileManager.default.fileExists(atPath: versionsDir.path) {
                            let versionContents = try FileManager.default.contentsOfDirectory(at: versionsDir, includingPropertiesForKeys: nil)
                            print("     Versions:")
                            for version in versionContents {
                                print("       - \(version.lastPathComponent)")
                                let binDir = version.appendingPathComponent("bin")
                                if FileManager.default.fileExists(atPath: binDir.path) {
                                    let binContents = try FileManager.default.contentsOfDirectory(at: binDir, includingPropertiesForKeys: nil)
                                    print("         bin contents:")
                                    for bin in binContents {
                                        print("           - \(bin.lastPathComponent)")
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("🔍 Error reading EmbeddedPython: \(error)")
            }
        }
        
        print("🔍 === END BUNDLE DEBUG ===")
    }
    
    private func initializeSelections() {
        // Ensure we have selections for all speakers, but clamp to valid channel range
        while speakerSelections.count < speakerLabels.count {
            let defaultChannel = min(speakerSelections.count, playbackChannels - 1)
            speakerSelections.append(max(0, defaultChannel))
        }
        
        // Ensure we have selections for both microphones, but clamp to valid channel range
        while micSelections.count < 2 {
            let defaultChannel = min(micSelections.count, max(recordingChannels - 1, 0))
            micSelections.append(max(0, defaultChannel))
        }
        
        // Clamp all existing values to valid ranges
        for i in 0..<speakerSelections.count {
            speakerSelections[i] = min(max(speakerSelections[i], 0), playbackChannels - 1)
        }
        
        for i in 0..<micSelections.count {
            micSelections[i] = min(max(micSelections[i], 0), max(recordingChannels - 1, 0))
        }
        
        print("🔧 Initialized speaker selections: \(speakerSelections) (max: \(playbackChannels - 1))")
        print("🔧 Initialized mic selections: \(micSelections) (max: \(max(recordingChannels - 1, 0)))")
    }
    
    private func ensureSelectionsCapacity(index: Int) {
        while speakerSelections.count <= index {
            speakerSelections.append(speakerSelections.count)
        }
    }
    
    private func autoMapChannels() {
        // Auto-assign channels sequentially
        speakerSelections = Array(0..<min(playbackChannels, speakerLabels.count))
        micSelections = Array(0..<min(recordingChannels, 2))
    }
    
    private func saveMapping() {
        channelMapping["output_channels"] = Array(speakerSelections.prefix(speakerLabels.count))
        channelMapping["input_channels"] = Array(micSelections.prefix(2))
        
        onSave()
        isPresented = false
        dismiss()
    }
    
    private func testChannel(index: Int, isOutput: Bool) {
        guard !isTestingChannel else { return }
        guard index < speakerSelections.count else { return }
        
        isTestingChannel = true
        testingChannelIndex = index
        
        // Debug: Let's find out what's actually in the bundle
        print("🔍 Bundle.main.resourceURL: \(Bundle.main.resourceURL?.path ?? "nil")")
        print("🔍 Bundle.main.bundleURL: \(Bundle.main.bundleURL.path)")
        
        // Check various possible paths for embedded Python
        let possiblePaths = [
            Bundle.main.resourceURL?.appendingPathComponent("EmbeddedPython/Python.framework/Versions/3.9/bin/python3"),
            Bundle.main.resourceURL?.appendingPathComponent("EmbeddedPython/Python.framework/Versions/Current/bin/python3"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/EmbeddedPython/Python.framework/Versions/3.9/bin/python3"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/EmbeddedPython/Python.framework/Versions/Current/bin/python3"),
        ].compactMap { $0 }
        
        print("🔍 Checking possible Python paths:")
        for path in possiblePaths {
            let exists = FileManager.default.fileExists(atPath: path.path)
            print("   \(path.path) - \(exists ? "EXISTS" : "NOT FOUND")")
        }
        
        // Also check what's actually in the EmbeddedPython directory
        if let resourceURL = Bundle.main.resourceURL {
            let embeddedDir = resourceURL.appendingPathComponent("EmbeddedPython")
            print("🔍 Contents of EmbeddedPython directory:")
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: embeddedDir, includingPropertiesForKeys: nil)
                for item in contents {
                    print("   \(item.lastPathComponent)")
                }
            } catch {
                print("   Could not read EmbeddedPython directory: \(error)")
            }
        }
        
        // Use the same channel testing approach as in the original ChannelMappingView
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        
        // Try to find embedded Python
        var foundEmbeddedPython: URL? = nil
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                foundEmbeddedPython = path
                break
            }
        }
        
        if let py = foundEmbeddedPython {
            process.executableURL = py
            process.arguments = [
                scriptPath("channel_tester.py"),
                "--channels", String(playbackChannels),
                "--channel", String(speakerSelections[index])
            ] + (useTone ? ["--tone"] : [])
            
            // Set up comprehensive Python environment
            let pythonHome = py.deletingLastPathComponent().deletingLastPathComponent().path
            let pythonPath = scriptsRoot.path
            let libPath = "\(pythonHome)/lib/python3.9"
            let sitePackages = "\(libPath)/site-packages"
            
            process.environment = [
                "PYTHONHOME": pythonHome,
                "PYTHONPATH": "\(pythonPath):\(libPath):\(sitePackages)",
                "PATH": "/usr/bin:/bin:\(py.deletingLastPathComponent().path)",
                "DYLD_LIBRARY_PATH": "\(pythonHome)/lib"
            ]
            
            print("🔍 Using embedded Python: \(py.path)")
            print("🔍 PYTHONHOME: \(pythonHome)")
            print("🔍 PYTHONPATH: \(pythonPath):\(libPath):\(sitePackages)")
        } else {
            // Fallback to system Python, but first try to install numpy there
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var args = [
                "python3",
                scriptPath("channel_tester.py"),
                "--device", playbackDevice,
                "--channels", String(playbackChannels),
                "--channel", String(speakerSelections[index])
            ]
            if useTone { args.append("--tone") }
            process.arguments = args
            print("⚠️ Using system Python - embedded Python not found at any expected location.")
            print("💡 Consider installing numpy in system Python: pip3 install numpy sounddevice")
        }
        
        // Capture both stdout and stderr for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                    print("📝 Channel test output: \(output)")
                }
                
                if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                    print("❌ Channel test error: \(error)")
                }
                
                if process.terminationStatus != 0 {
                    print("⚠️ Channel test failed with exit code: \(process.terminationStatus)")
                } else {
                    print("✅ Channel test completed successfully")
                }
            } catch {
                print("❌ Failed to run channel test: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isTestingChannel = false
                self.testingChannelIndex = nil
            }
        }
    }
}
