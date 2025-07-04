#if canImport(SwiftUI)
import SwiftUI
EarprintApp.main()
#else
import Foundation
print("Earprint requires macOS with SwiftUI.\n")
#endif
