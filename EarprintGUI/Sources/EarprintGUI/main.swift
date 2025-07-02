#if canImport(SwiftUI)
import SwiftUI
EarprintApp.main()
#else
import Foundation
print("EarprintGUI requires macOS with SwiftUI.\n")
#endif