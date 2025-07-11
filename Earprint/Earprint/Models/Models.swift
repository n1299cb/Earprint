import Foundation

// MARK: - Shared Configuration Models

/// Configuration for processing operations
struct ProcessingConfiguration {
    let measurementDir: String
    let testSignal: String
    let channelBalance: String?
    let targetLevel: String?
    let playbackDevice: String?
    let recordingDevice: String?
    let outputChannels: [Int]?
    let inputChannels: [Int]?
    
    // Processing Options
    let enableCompensation: Bool
    let headphoneEqEnabled: Bool
    let headphoneFile: String?
    let compensationType: String?
    let diffuseField: Bool
    
    // X-Curve Settings
    let xCurveAction: String
    let xCurveType: String?
    let xCurveInCapture: Bool
    
    // Advanced Settings
    let decayTime: String
    let decayEnabled: Bool
    let specificLimit: String
    let specificLimitEnabled: Bool
    let genericLimit: String
    let genericLimitEnabled: Bool
    let frCombinationMethod: String
    let frCombinationEnabled: Bool
    let roomCorrection: Bool
    let roomTarget: String
    let micCalibration: String
    let interactiveDelays: Bool
}

/// Configuration for recording operations
struct RecordingConfiguration {
    let measurementDir: String
    let testSignal: String
    let playbackDevice: String
    let recordingDevice: String
    let outputFile: String?
    let speakerLayout: String?
    let recordingGroup: String?
    
    let outputChannels: [Int]?
    let inputChannels: [Int]?
    
    init(
        measurementDir: String,
        testSignal: String,
        playbackDevice: String,
        recordingDevice: String,
        outputFile: String? = nil,
        speakerLayout: String? = nil,
        recordingGroup: String? = nil,
        outputChannels: [Int]? = nil,
        inputChannels: [Int]? = nil
    ) {
        self.measurementDir = measurementDir
        self.testSignal = testSignal
        self.playbackDevice = playbackDevice
        self.recordingDevice = recordingDevice
        self.outputFile = outputFile
        self.speakerLayout = speakerLayout
        self.recordingGroup = recordingGroup
        self.outputChannels = outputChannels
        self.inputChannels = inputChannels
    }
}

// MARK: - Processing State
enum ProcessingState: Equatable {
    case idle
    case running(progress: Double?, remainingTime: Double?)
    case completed
    case failed(Error)
    
    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.completed, .completed):
            return true
        case let (.running(p1, t1), .running(p2, t2)):
            return p1 == p2 && t1 == t2
        case let (.failed(e1), .failed(e2)):
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Speaker Layout Support Types (add to Models.swift)

struct SpeakerLayoutInfo {
    let name: String
    let displayName: String
    let groups: [RecordingGroup]
    let icon: String
}

struct RecordingGroup {
    let name: String
    let speakers: [String]
    
    var filename: String {
        return "\(name).wav"
    }
}

// MARK: - File Validation
struct FileValidationResult {
    let isValid: Bool
    let errorMessage: String?
    let suggestions: [String]
}

// MARK: - Recording Info
struct RecordingInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let dateModified: Date
    let size: Int64
    let isDirectory: Bool
    
    static func == (lhs: RecordingInfo, rhs: RecordingInfo) -> Bool {
        lhs.path == rhs.path
    }
}

// MARK: - Error Types
enum ProcessingError: LocalizedError {
    case invalidMeasurementDirectory
    case invalidTestSignal
    case missingCalibrationFile(String)
    case missingHeadphoneFile(String)
    case processFailure(Int32)
    
    var errorDescription: String? {
        switch self {
        case .invalidMeasurementDirectory:
            return "Invalid measurement directory"
        case .invalidTestSignal:
            return "Invalid test signal"
        case .missingCalibrationFile(let path):
            return "Missing calibration file: \(path)"
        case .missingHeadphoneFile(let path):
            return "Missing headphone file: \(path)"
        case .processFailure(let status):
            return "Process failed with status: \(status)"
        }
    }
}
