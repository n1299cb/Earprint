//
//  PreferencesView.swift
//  EarprintGUI
//
//  Created by Christian Blair on 7/3/25.
//


#if canImport(SwiftUI)
import SwiftUI

struct PreferencesView: View {
    @AppStorage("defaultMeasurementDir") private var defaultMeasurementDir: String = ""

    var body: some View {
        Form {
            HStack {
                TextField("Default Measurement Directory", text: $defaultMeasurementDir)
                Button("Browse") {
                    if let path = openPanel(directory: true, startPath: defaultMeasurementDir) {
                        defaultMeasurementDir = path
                    }
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
