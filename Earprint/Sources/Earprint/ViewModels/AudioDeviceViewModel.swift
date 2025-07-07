#if canImport(SwiftUI) && canImport(CoreAudio)
import SwiftUI
import CoreAudio
import Foundation

// MARK: - Audio Device Models
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let maxInputChannels: Int
    let maxOutputChannels: Int
    let nominalSampleRate: Double
    let isDefaultInput: Bool
    let isDefaultOutput: Bool
    let isRunning: Bool
    
    var canRecord: Bool { maxInputChannels > 0 }
    var canPlayback: Bool { maxOutputChannels > 0 }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

struct AudioLevelMeter {
    let channelCount: Int
    let levels: [Float]
    let peak: Float
    let timestamp: Date
}

// MARK: - Channel Mapping
struct ChannelMapping {
    let inputChannels: [Int]
    let outputChannels: [Int]
    let deviceInputChannels: Int
    let deviceOutputChannels: Int
    
    var isValid: Bool {
        inputChannels.allSatisfy { $0 < deviceInputChannels } &&
        outputChannels.allSatisfy { $0 < deviceOutputChannels }
    }
}

// MARK: - Audio Device ViewModel
@MainActor
final class AudioDeviceViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedInputDevice: AudioDevice?
    @Published var selectedOutputDevice: AudioDevice?
    @Published var channelMapping: ChannelMapping?
    @Published var isMonitoring: Bool = false
    @Published var inputLevels: AudioLevelMeter?
    @Published var outputLevels: AudioLevelMeter?
    @Published var autoMapChannels: Bool = true
    @Published var deviceWarnings: [String] = []
    
    // MARK: - Private Properties
    private var levelMonitoringTimer: Timer?
    
    init() {
        refreshDevices()
    }
    
    deinit {
        // Timer cleanup will happen automatically when the object is deallocated
        // We can't access @MainActor properties from deinit
    }
    
    // MARK: - Public Methods
    func refreshDevices() {
        Task {
            let (inputs, outputs) = await scanAudioDevices()
            
            self.inputDevices = inputs
            self.outputDevices = outputs
            
            // Update selected devices if they're no longer available
            if let selected = selectedInputDevice,
               !inputs.contains(where: { $0.id == selected.id }) {
                selectedInputDevice = inputs.first { $0.isDefaultInput } ?? inputs.first
            }
            
            if let selected = selectedOutputDevice,
               !outputs.contains(where: { $0.id == selected.id }) {
                selectedOutputDevice = outputs.first { $0.isDefaultOutput } ?? outputs.first
            }
            
            updateChannelMapping()
            updateDeviceWarnings()
        }
    }
    
    func selectInputDevice(_ device: AudioDevice) {
        selectedInputDevice = device
        updateChannelMapping()
        updateDeviceWarnings()
    }
    
    func selectOutputDevice(_ device: AudioDevice) {
        selectedOutputDevice = device
        updateChannelMapping()
        updateDeviceWarnings()
    }
    
    func setChannelMapping(input: [Int], output: [Int]) {
        guard let inputDevice = selectedInputDevice,
              let outputDevice = selectedOutputDevice else { return }
        
        channelMapping = ChannelMapping(
            inputChannels: input,
            outputChannels: output,
            deviceInputChannels: inputDevice.maxInputChannels,
            deviceOutputChannels: outputDevice.maxOutputChannels
        )
        updateDeviceWarnings()
    }
    
    func autoMapChannelsAction() {
        guard let inputDevice = selectedInputDevice,
              let outputDevice = selectedOutputDevice else { return }
        
        let inputChannels = Array(0..<min(2, inputDevice.maxInputChannels))
        let outputChannels = Array(0..<min(2, outputDevice.maxOutputChannels))
        
        setChannelMapping(input: inputChannels, output: outputChannels)
    }
    
    func startLevelMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        levelMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevels()
            }
        }
    }
    
    func stopLevelMonitoring() {
        isMonitoring = false
        levelMonitoringTimer?.invalidate()
        levelMonitoringTimer = nil
        inputLevels = nil
        outputLevels = nil
    }
    
    func validateDeviceConfiguration() -> [String] {
        var warnings: [String] = []
        
        if selectedInputDevice == nil {
            warnings.append("No input device selected")
        }
        
        if selectedOutputDevice == nil {
            warnings.append("No output device selected")
        }
        
        if let mapping = channelMapping, !mapping.isValid {
            warnings.append("Invalid channel mapping")
        }
        
        if let input = selectedInputDevice, input.maxInputChannels == 0 {
            warnings.append("Selected input device has no input channels")
        }
        
        if let output = selectedOutputDevice, output.maxOutputChannels == 0 {
            warnings.append("Selected output device has no output channels")
        }
        
        // Check sample rate compatibility
        if let input = selectedInputDevice,
           let output = selectedOutputDevice,
           abs(input.nominalSampleRate - output.nominalSampleRate) > 1.0 {
            warnings.append("Input and output devices have different sample rates")
        }
        
        return warnings
    }
    
    func getDeviceDisplayName(_ device: AudioDevice) -> String {
        var name = device.name
        
        if device.isDefaultInput && device.canRecord {
            name += " (Default Input)"
        }
        
        if device.isDefaultOutput && device.canPlayback {
            name += " (Default Output)"
        }
        
        return name
    }
    
    func getChannelSummary(_ device: AudioDevice) -> String {
        var components: [String] = []
        
        if device.maxInputChannels > 0 {
            components.append("\(device.maxInputChannels) in")
        }
        
        if device.maxOutputChannels > 0 {
            components.append("\(device.maxOutputChannels) out")
        }
        
        return components.joined(separator: ", ")
    }
    
    func getSampleRateText(_ device: AudioDevice) -> String {
        let rate = device.nominalSampleRate
        if rate >= 1000 {
            return String(format: "%.1fkHz", rate / 1000)
        } else {
            return String(format: "%.0fHz", rate)
        }
    }
    
    // MARK: - Private Methods
    private func scanAudioDevices() async -> ([AudioDevice], [AudioDevice]) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let devices = AudioDeviceScanner.getAllAudioDevices()
                let inputs = devices.filter { $0.canRecord }
                let outputs = devices.filter { $0.canPlayback }
                continuation.resume(returning: (inputs, outputs))
            }
        }
    }
    
    private func updateChannelMapping() {
        guard autoMapChannels else { return }
        autoMapChannelsAction()
    }
    
    private func updateDeviceWarnings() {
        deviceWarnings = validateDeviceConfiguration()
    }
    
    private func updateAudioLevels() {
        // Mock implementation for level monitoring
        // In a real implementation, you would set up proper Core Audio level monitoring
        
        if let inputDevice = selectedInputDevice, inputDevice.canRecord {
            let channelCount = inputDevice.maxInputChannels
            let levels = Array(repeating: Float.random(in: -60...0), count: min(channelCount, 8))
            let peak = levels.max() ?? -60.0
            
            inputLevels = AudioLevelMeter(
                channelCount: channelCount,
                levels: levels,
                peak: peak,
                timestamp: Date()
            )
        }
        
        if let outputDevice = selectedOutputDevice, outputDevice.canPlayback {
            let channelCount = outputDevice.maxOutputChannels
            let levels = Array(repeating: Float.random(in: -60...0), count: min(channelCount, 8))
            let peak = levels.max() ?? -60.0
            
            outputLevels = AudioLevelMeter(
                channelCount: channelCount,
                levels: levels,
                peak: peak,
                timestamp: Date()
            )
        }
    }
}

// MARK: - Audio Device Scanner (Non-MainActor)
private struct AudioDeviceScanner {
    
    static func getAllAudioDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                           &propertyAddress,
                                           0,
                                           nil,
                                           &dataSize) == noErr else { return devices }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
        
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       &propertyAddress,
                                       0,
                                       nil,
                                       &dataSize,
                                       &deviceIDs) == noErr else { return devices }
        
        for deviceID in deviceIDs {
            if let device = createAudioDevice(from: deviceID) {
                devices.append(device)
            }
        }
        
        return devices
    }
    
    private static func createAudioDevice(from deviceID: AudioDeviceID) -> AudioDevice? {
        guard let name = getDeviceName(deviceID),
              let uid = getDeviceUID(deviceID) else { return nil }
        
        let inputChannels = getDeviceChannelCount(deviceID, scope: kAudioObjectPropertyScopeInput)
        let outputChannels = getDeviceChannelCount(deviceID, scope: kAudioObjectPropertyScopeOutput)
        let sampleRate = getDeviceSampleRate(deviceID)
        
        return AudioDevice(
            id: deviceID,
            name: name,
            uid: uid,
            maxInputChannels: inputChannels,
            maxOutputChannels: outputChannels,
            nominalSampleRate: sampleRate,
            isDefaultInput: isDefaultDevice(deviceID, scope: kAudioObjectPropertyScopeInput),
            isDefaultOutput: isDefaultDevice(deviceID, scope: kAudioObjectPropertyScopeOutput),
            isRunning: isDeviceRunning(deviceID)
        )
    }
    
    private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr else { return nil }
        
        let stringPointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        defer { stringPointer.deallocate() }
        
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, stringPointer) == noErr,
              let string = stringPointer.pointee else { return nil }
        
        return string as String
    }
    
    private static func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr else { return nil }
        
        let stringPointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        defer { stringPointer.deallocate() }
        
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, stringPointer) == noErr,
              let string = stringPointer.pointee else { return nil }
        
        return string as String
    }
    
    private static func getDeviceChannelCount(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr else { return 0 }
        
        // Allocate buffer for AudioBufferList
        let bufferListSize = Int(dataSize)
        let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: bufferListSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPointer.deallocate() }
        
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer) == noErr else { return 0 }
        
        let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        _ = Int(bufferList.pointee.mNumberBuffers) // Acknowledge unused variable
        
        var channelCount = 0
        let buffersPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffersPointer {
            channelCount += Int(buffer.mNumberChannels)
        }
        
        return channelCount
    }
    
    private static func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<Float64>.size)
        
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &sampleRate) == noErr else {
            return 44100.0 // Default fallback
        }
        
        return sampleRate
    }
    
    private static func isDefaultDevice(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        let selector = scope == kAudioObjectPropertyScopeInput ?
            kAudioHardwarePropertyDefaultInputDevice :
            kAudioHardwarePropertyDefaultOutputDevice
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var defaultDeviceID: AudioDeviceID = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       &propertyAddress,
                                       0,
                                       nil,
                                       &dataSize,
                                       &defaultDeviceID) == noErr else { return false }
        
        return defaultDeviceID == deviceID
    }
    
    private static func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isRunning: UInt32 = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &isRunning) == noErr else {
            return false
        }
        
        return isRunning != 0
    }
}

#else
// Non-macOS stub implementation
struct AudioDevice: Identifiable, Hashable {
    let id = 0
    let name = ""
    let uid = ""
    let maxInputChannels = 0
    let maxOutputChannels = 0
    let nominalSampleRate = 44100.0
    let isDefaultInput = false
    let isDefaultOutput = false
    let isRunning = false
    var canRecord: Bool { false }
    var canPlayback: Bool { false }
}

struct AudioLevelMeter {
    let channelCount = 0
    let levels: [Float] = []
    let peak: Float = 0
    let timestamp = Date()
}

struct ChannelMapping {
    let inputChannels: [Int] = []
    let outputChannels: [Int] = []
    let deviceInputChannels = 0
    let deviceOutputChannels = 0
    var isValid: Bool { false }
}

final class AudioDeviceViewModel: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedInputDevice: AudioDevice?
    @Published var selectedOutputDevice: AudioDevice?
    @Published var channelMapping: ChannelMapping?
    @Published var isMonitoring: Bool = false
    @Published var inputLevels: AudioLevelMeter?
    @Published var outputLevels: AudioLevelMeter?
    @Published var autoMapChannels: Bool = true
    @Published var deviceWarnings: [String] = []
    
    func refreshDevices() {}
    func selectInputDevice(_ device: AudioDevice) {}
    func selectOutputDevice(_ device: AudioDevice) {}
    func setChannelMapping(input: [Int], output: [Int]) {}
    func autoMapChannelsAction() {}
    func startLevelMonitoring() {}
    func stopLevelMonitoring() {}
    func validateDeviceConfiguration() -> [String] { return [] }
    func getDeviceDisplayName(_ device: AudioDevice) -> String { return "" }
    func getChannelSummary(_ device: AudioDevice) -> String { return "" }
    func getSampleRateText(_ device: AudioDevice) -> String { return "" }
}
#endif
