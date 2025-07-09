#if canImport(SwiftUI)
import SwiftUI
import Charts
import UniformTypeIdentifiers

struct FrequencyVisualizationView: View {
    @Binding var measurementDir: String
    
    // Data Management
    @State private var csvFiles: [CSVFile] = []
    @State private var selectedFiles: Set<String> = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""
    
    // Chart Configuration
    @State private var frequencyRange: ClosedRange<Double> = 20...20000
    @State private var amplitudeRange: ClosedRange<Double> = -40...10
    @State private var useLogScale: Bool = true
    @State private var showSmoothed: Bool = true
    @State private var lineWidth: Double = 2.0
    
    // Export CSV functionality
    @State private var showExportSheet: Bool = false
    @State private var exportProgress: Double = 0.0
    @State private var isExporting: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            headerSection
                .padding()
                .background(.regularMaterial, in: Rectangle())
            
            Divider()
            
            // Main content
            if csvFiles.isEmpty && !isLoading {
                emptyStateView
            } else {
                VStack(spacing: 16) {
                    // File selection
                    fileSelectionSection
                    
                    // Chart display
                    chartSection
                    
                    // Chart controls
                    chartControlsSection
                }
                .padding()
            }
        }
        .onAppear(perform: loadCSVFiles)
        .onChange(of: measurementDir) { _ in loadCSVFiles() }
        .sheet(isPresented: $showExportSheet) {
            csvExportSheet
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frequency Response Visualization")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Interactive charts from CSV measurement data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Export CSV Data") {
                        showExportSheet = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(measurementDir.isEmpty)
                    
                    Button("Refresh") {
                        loadCSVFiles()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - File Selection Section
    
    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available CSV Files")
                .font(.headline)
                .fontWeight(.semibold)
            
            if csvFiles.isEmpty {
                Text("No CSV files found in measurement directory")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(csvFiles) { csvFile in
                        CSVFileCard(
                            csvFile: csvFile,
                            isSelected: selectedFiles.contains(csvFile.id),
                            onToggle: {
                                if selectedFiles.contains(csvFile.id) {
                                    selectedFiles.remove(csvFile.id)
                                } else {
                                    selectedFiles.insert(csvFile.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frequency Response")
                .font(.headline)
                .fontWeight(.semibold)
            
            if selectedFiles.isEmpty {
                Text("Select CSV files to display frequency response data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            } else {
                frequencyResponseChart
                    .frame(height: 400)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var frequencyResponseChart: some View {
        Chart {
            ForEach(csvFiles.filter { selectedFiles.contains($0.id) }) { csvFile in
                ForEach(csvFile.data, id: \.frequency) { dataPoint in
                    LineMark(
                        x: .value("Frequency", useLogScale ? log10(dataPoint.frequency) : dataPoint.frequency),
                        y: .value("Amplitude", dataPoint.amplitude)
                    )
                    .foregroundStyle(csvFile.color)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth))
                }
            }
        }
        .chartXScale(domain: useLogScale ?
            log10(frequencyRange.lowerBound)...log10(frequencyRange.upperBound) :
            frequencyRange.lowerBound...frequencyRange.upperBound
        )
        .chartYScale(domain: amplitudeRange)
        .chartXAxis {
            AxisMarks { value in
                if useLogScale {
                    let freq = pow(10, value.as(Double.self) ?? 1)
                    AxisValueLabel {
                        Text(formatFrequency(freq))
                    }
                    AxisGridLine()
                    AxisTick()
                } else {
                    AxisValueLabel()
                    AxisGridLine()
                    AxisTick()
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                AxisGridLine()
                AxisTick()
            }
        }
        .chartLegend(position: .bottom, alignment: .leading) {
            HStack {
                ForEach(csvFiles.filter { selectedFiles.contains($0.id) }) { csvFile in
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(csvFile.color)
                            .frame(width: 12, height: 2)
                        Text(csvFile.name)
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    // MARK: - Chart Controls Section
    
    private var chartControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chart Settings")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                HStack {
                    Toggle("Logarithmic Frequency Scale", isOn: $useLogScale)
                    Spacer()
                    Toggle("Show Smoothed Data", isOn: $showSmoothed)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Width: \(lineWidth, specifier: "%.1f")")
                        .font(.caption)
                    Slider(value: $lineWidth, in: 0.5...5.0, step: 0.5)
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Frequency Range")
                            .font(.caption)
                        HStack {
                            TextField("Min", value: .constant(frequencyRange.lowerBound), format: .number)
                                .frame(width: 60)
                            Text("to")
                            TextField("Max", value: .constant(frequencyRange.upperBound), format: .number)
                                .frame(width: 60)
                            Text("Hz")
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("Amplitude Range")
                            .font(.caption)
                        HStack {
                            TextField("Min", value: .constant(amplitudeRange.lowerBound), format: .number)
                                .frame(width: 60)
                            Text("to")
                            TextField("Max", value: .constant(amplitudeRange.upperBound), format: .number)
                                .frame(width: 60)
                            Text("dB")
                        }
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Frequency Response Data")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Run post-processing with CSV export enabled to generate visualization data")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Export CSV Data") {
                showExportSheet = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(measurementDir.isEmpty)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - CSV Export Sheet
    
    private var csvExportSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export Frequency Response Data")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Generate CSV files from your measurement data for visualization and analysis")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                if isExporting {
                    VStack(spacing: 12) {
                        ProgressView(value: exportProgress)
                            .frame(maxWidth: .infinity)
                        
                        Text("Exporting frequency response data...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The following CSV files will be generated:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• headphones-raw.csv - Raw headphone response")
                            Text("• headphones-smoothed.csv - Smoothed headphone response")
                            Text("• hrir-response.csv - HRIR frequency data")
                            Text("• export_summary.txt - Export details")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        showExportSheet = false
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Export CSV Files") {
                        exportCSVData()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || measurementDir.isEmpty)
                }
            }
            .padding()
            .navigationTitle("Export CSV Data")
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadCSVFiles() {
        isLoading = true
        errorMessage = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            let plotsDir = URL(fileURLWithPath: measurementDir).appendingPathComponent("plots")
            
            guard FileManager.default.fileExists(atPath: plotsDir.path) else {
                DispatchQueue.main.async {
                    self.csvFiles = []
                    self.isLoading = false
                }
                return
            }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(at: plotsDir,
                                                                       includingPropertiesForKeys: nil)
                let csvFiles = files.filter { $0.pathExtension.lowercased() == "csv" }
                
                var loadedFiles: [CSVFile] = []
                
                for csvFile in csvFiles {
                    if let parsedFile = parseCSVFile(csvFile) {
                        loadedFiles.append(parsedFile)
                    }
                }
                
                DispatchQueue.main.async {
                    self.csvFiles = loadedFiles.sorted { $0.name < $1.name }
                    self.isLoading = false
                    
                    // Auto-select headphone files if available
                    for file in self.csvFiles {
                        if file.name.contains("headphone") {
                            self.selectedFiles.insert(file.id)
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Error loading CSV files: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func parseCSVFile(_ fileURL: URL) -> CSVFile? {
        do {
            let content = try String(contentsOf: fileURL)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            guard lines.count > 1 else { return nil }
            
            let headers = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            // Find frequency and amplitude columns
            guard let freqIndex = headers.firstIndex(where: { $0.lowercased().contains("freq") }),
                  let ampIndex = findAmplitudeColumn(headers) else {
                return nil
            }
            
            var dataPoints: [FrequencyDataPoint] = []
            
            for line in lines.dropFirst() {
                let values = line.components(separatedBy: ",")
                guard values.count > max(freqIndex, ampIndex),
                      let frequency = Double(values[freqIndex].trimmingCharacters(in: .whitespaces)),
                      let amplitude = Double(values[ampIndex].trimmingCharacters(in: .whitespaces)) else {
                    continue
                }
                
                dataPoints.append(FrequencyDataPoint(frequency: frequency, amplitude: amplitude))
            }
            
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            let color = colorForFile(fileName)
            
            return CSVFile(
                id: fileURL.path,
                name: fileName,
                url: fileURL,
                data: dataPoints,
                color: color
            )
            
        } catch {
            print("Error parsing CSV file \(fileURL.lastPathComponent): \(error)")
            return nil
        }
    }
    
    private func findAmplitudeColumn(_ headers: [String]) -> Int? {
        // Look for amplitude/db columns, prefer left channel or smoothed data
        let priorityColumns = [
            "left_db", "left", "left_smoothed",
            "amplitude", "db", "magnitude",
            "right_db", "right", "right_smoothed"
        ]
        
        for priority in priorityColumns {
            if let index = headers.firstIndex(where: { $0.lowercased().contains(priority.lowercased()) }) {
                return index
            }
        }
        
        // Fallback to second column if it's numeric
        return headers.count > 1 ? 1 : nil
    }
    
    private func colorForFile(_ fileName: String) -> Color {
        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .pink, .yellow, .cyan]
        let hash = fileName.hashValue
        return colors[abs(hash) % colors.count]
    }
    
    private func formatFrequency(_ frequency: Double) -> String {
        if frequency >= 1000 {
            return String(format: "%.0fk", frequency / 1000)
        } else {
            return String(format: "%.0f", frequency)
        }
    }
    
    private func exportCSVData() {
        guard !measurementDir.isEmpty else { return }
        
        isExporting = true
        exportProgress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate export progress
            let scriptPath = Bundle.main.path(forResource: "export_frequency_response", ofType: "py") ??
                            URL(fileURLWithPath: measurementDir).appendingPathComponent("../Scripts/export_frequency_response.py").path
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", scriptPath, "--measurement_dir", measurementDir]
            
            do {
                try process.run()
                
                // Simulate progress updates
                for i in 1...10 {
                    DispatchQueue.main.async {
                        self.exportProgress = Double(i) / 10.0
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showExportSheet = false
                    self.loadCSVFiles() // Refresh the file list
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Export failed: \(error.localizedDescription)"
                    self.isExporting = false
                }
            }
        }
    }
}

// MARK: - Data Models

struct CSVFile: Identifiable {
    let id: String
    let name: String
    let url: URL
    let data: [FrequencyDataPoint]
    let color: Color
}

struct FrequencyDataPoint {
    let frequency: Double
    let amplitude: Double
}

// MARK: - CSV File Card Component

struct CSVFileCard: View {
    let csvFile: CSVFile
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(csvFile.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(csvFile.color)
                    }
                }
                
                HStack {
                    Text("\(csvFile.data.count) points")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Rectangle()
                        .fill(csvFile.color)
                        .frame(width: 16, height: 3)
                        .cornerRadius(1.5)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? csvFile.color.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? csvFile.color : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#endif
