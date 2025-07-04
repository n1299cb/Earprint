#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct RoomResponseView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    var measurementDir: String
    var testSignal: String
    var playbackDevice: String
    var recordingDevice: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("Capture a room response for room correction processing.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Record Room Response") {
                viewModel.recordRoomResponse(measurementDir: measurementDir,
                                            testSignal: testSignal,
                                            playbackDevice: playbackDevice,
                                            recordingDevice: recordingDevice)
            }
            .disabled(measurementDir.isEmpty || testSignal.isEmpty)
            if viewModel.isRunning {
                if let progress = viewModel.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Button("Clear Log") { viewModel.clearLog() }
                    .disabled(viewModel.log.isEmpty)
                Button("Save Log") {
                    if let url = savePanel(startPath: measurementDir) {
                        try? viewModel.log.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                .disabled(viewModel.log.isEmpty)
            }
            ScrollView {
                Text(viewModel.log)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    func savePanel(startPath: String) -> URL? {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.directoryURL = URL(fileURLWithPath: startPath)
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return nil
        #endif
    }
}
#endif