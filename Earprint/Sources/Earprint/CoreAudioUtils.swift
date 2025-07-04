#if os(macOS)
import CoreAudio
import AudioToolbox

struct CADeviceInfo {
    let deviceID: AudioDeviceID
    let name: String
    let maxInput: Int
    let maxOutput: Int
}

enum CoreAudioUtils {
    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return 0 }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var channels = 0
        for buffer in buffers {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    static func queryDevices() -> (devices: [CADeviceInfo], defaultInput: AudioDeviceID?, defaultOutput: AudioDeviceID?) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else {
            return ([], nil, nil)
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids)

        var devices: [CADeviceInfo] = []
        for id in ids {
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: CFString = "" as CFString
            var size = UInt32(MemoryLayout<CFString>.size)
            let status = withUnsafeMutablePointer(to: &cfName) { ptr -> OSStatus in
                AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &size, ptr)
            }
            if status != noErr {
                continue
            }
            let inputCh = channelCount(deviceID: id, scope: kAudioDevicePropertyScopeInput)
            let outputCh = channelCount(deviceID: id, scope: kAudioDevicePropertyScopeOutput)
            devices.append(CADeviceInfo(deviceID: id, name: cfName as String, maxInput: inputCh, maxOutput: outputCh))
        }

        var defaultInput: AudioDeviceID = 0
        var defaultOutput: AudioDeviceID = 0
        var s = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defAddr, 0, nil, &s, &defaultInput) != noErr {
            defaultInput = 0
        }
        defAddr.mSelector = kAudioHardwarePropertyDefaultOutputDevice
        s = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defAddr, 0, nil, &s, &defaultOutput) != noErr {
            defaultOutput = 0
        }

        return (devices, defaultInput == 0 ? nil : defaultInput, defaultOutput == 0 ? nil : defaultOutput)
    }
}
#endif