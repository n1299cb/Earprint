#if canImport(SwiftUI)
import SwiftUI
import AppKit

struct VisualizationView: View {
    var measurementDir: String
    @State private var images: [String] = []
    @State private var selectedImage: String?

    var body: some View {
        HStack {
            VStack {
                Button("Refresh") { loadImages() }
                List(images, id: \.self, selection: $selectedImage) { item in
                    Text(URL(fileURLWithPath: item).lastPathComponent)
                }
            }
            if let image = selectedImage, let nsImage = NSImage(contentsOfFile: image) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("No Image")
            }
        }
        .onAppear { loadImages() }
        .padding()
    }

    func loadImages() {
        guard !measurementDir.isEmpty else { images = []; return }
        let plots = URL(fileURLWithPath: measurementDir).appendingPathComponent("plots")
        guard let enumerator = FileManager.default.enumerator(at: plots, includingPropertiesForKeys: nil) else {
            images = []
            return
        }
        images = enumerator.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            return url.pathExtension.lowercased() == "png" ? url.path : nil
        }.sorted()
    }
}
#endif