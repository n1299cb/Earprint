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
            
            // Main content
            HStack(alignment: .top, spacing: 0) {
                // Speaker mapping section
                speakerSection
                
                Divider()
                
                // Microphone mapping section
                microphoneSection
            }
            
            Divider()
            
            // Footer with warnings and actions
            footerView
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            initializeSelections()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Channel Mapping")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Assign speakers and microphones to audio device channels")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Test signal controls
            VStack(alignment: .trailing, spacing: 8) {
                Text("Test Signal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Test Signal", selection: $useTone) {
                    Text("1 kHz Tone").tag(true)
                    Text("Pink Noise").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Speaker Section
    private var speakerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            }
            
            // Speaker assignments
            ScrollView {
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
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(speakerLabels.enumerated()), id: \.offset) { index, label in
                            speakerRow(index: index, label: label)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private func speakerRow(index: Int, label: String) -> some View {
        HStack(spacing: 12) {
            // Speaker label
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 60, alignment: .leading)
            
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
                    Text("Channel \(channel + 1)").tag(channel)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            
            Spacer()
            
            // Test button
            Button(action: {
                testChannel(index: index, isOutput: true)
            }) {
                HStack(spacing: 4) {
                    if isTestingChannel && testingChannelIndex == index {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "play.circle")
                    }
                    Text("Test")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isTestingChannel || index >= speakerSelections.count)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Microphone Section
    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            }
            
            // Microphone assignments
            VStack(spacing: 12) {
                let micLabels = ["Left Mic", "Right Mic"]
                
                ForEach(Array(micLabels.enumerated()), id: \.offset) { index, label in
                    microphoneRow(index: index, label: label)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private func microphoneRow(index: Int, label: String) -> some View {
        HStack(spacing: 12) {
            // Microphone label
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            
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
                    Text("Channel \(channel + 1)").tag(channel)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
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
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Reset to Auto") {
                    autoMapChannels()
                }
                .buttonStyle(.bordered)
                
                Button("Save Mapping") {
                    saveMapping()
                }
                .buttonStyle(.borderedProminent)
                .disabled(channelWarning != nil)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Helper Methods
    private func initializeSelections() {
        // Ensure we have selections for all speakers
        while speakerSelections.count < speakerLabels.count {
            speakerSelections.append(speakerSelections.count)
        }
        
        // Ensure we have selections for both microphones
        while micSelections.count < 2 {
            micSelections.append(micSelections.count)
        }
        
        // Clamp values to valid ranges
        for i in 0..<speakerSelections.count {
            speakerSelections[i] = min(speakerSelections[i], playbackChannels - 1)
        }
        
        for i in 0..<micSelections.count {
            micSelections[i] = min(micSelections[i], max(recordingChannels - 1, 0))
        }
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
        
        // Use the same channel testing approach as in the original ChannelMappingView
        let process = Process()
        process.currentDirectoryURL = scriptsRoot
        
        if let py = embeddedPythonURL {
            process.executableURL = py
            process.arguments = [
                scriptPath("channel_tester.py"),
                "--device", playbackDevice,
                "--channels", String(playbackChannels),
                "--channel", String(speakerSelections[index])
            ] + (useTone ? ["--tone"] : [])
            process.environment = [
                "PYTHONHOME": py.deletingLastPathComponent().deletingLastPathComponent().path,
                "PYTHONPATH": scriptsRoot.path
            ]
        } else {
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
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? process.run()
            process.waitUntilExit()
            
            DispatchQueue.main.async {
                self.isTestingChannel = false
                self.testingChannelIndex = nil
            }
        }
    }
}
