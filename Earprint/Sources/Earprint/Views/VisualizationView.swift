#if canImport(SwiftUI)
import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct VisualizationView: View {
    var measurementDir: String
    @State private var csvFiles: [String] = []
    @State private var selectedFile: String?

    var body: some View {
        HStack {
            VStack {
                Button("Refresh") { loadCSVFiles() }
                List(csvFiles, id: \.self, selection: $selectedFile) { file in
                    Text(URL(fileURLWithPath: file).lastPathComponent)
                }
            }
            if let path = selectedFile {
#if canImport(Charts)
                if #available(macOS 13, *) {
                    CSVChartView(filePath: path)
                } else {
                    Text("CSV charts require macOS 13")
                }
#else
                Text("CSV charts require the Charts framework")
#endif
            } else {
                Text("No Data")
            }
        }
        .onAppear { loadCSVFiles() }
        .padding()
    }

    func loadCSVFiles() {
        guard !measurementDir.isEmpty else { csvFiles = []; return }
        let plots = URL(fileURLWithPath: measurementDir).appendingPathComponent("plots")
        guard let enumerator = FileManager.default.enumerator(at: plots, includingPropertiesForKeys: nil) else {
            csvFiles = []
            return
        }
        csvFiles = enumerator.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            return url.pathExtension.lowercased() == "csv" ? url.path : nil
        }.sorted()
    }
}
#if canImport(Charts)
@available(macOS 13, *)
struct CSVChartView: View {
    var filePath: String
    @State private var dataPoints: [DataPoint] = []

    struct DataPoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
    }

    var body: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value("X", point.x),
                y: .value("Y", point.y)
            )
        }
        .chartXAxisLabel("Frequency")
        .chartYAxisLabel("Value")
        .onAppear { loadData() }
    }

    func loadData() {
        guard let content = try? String(contentsOfFile: filePath) else { return }
        let lines = content.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else { return }
        var result: [DataPoint] = []
        for line in lines.dropFirst() {
            let comps = line.split(separator: ",")
            if comps.count >= 2,
               let x = Double(comps[0]),
               let y = Double(comps[1]) {
                result.append(DataPoint(x: x, y: y))
            }
        }
        dataPoints = result.sorted { $0.x < $1.x }
    }
}
#endif
#endif