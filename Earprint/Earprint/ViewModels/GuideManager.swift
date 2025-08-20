import SwiftUI

// MARK: - Guide Manager
@MainActor
class GuideManager: ObservableObject {
    @Published var isActive = false
    @Published var currentStep: GuideStep?
    @Published var completedSteps: Set<String> = []
    
    private var steps: [GuideStep] = []
    private var currentIndex = 0
    
    func startGuide(_ guideType: GuideType) {
        steps = guideType.steps
        currentIndex = 0
        currentStep = steps.first
        isActive = true
    }
    
    func nextStep() {
        guard currentIndex < steps.count - 1 else {
            endGuide()
            return
        }
        
        if let currentStep = currentStep {
            completedSteps.insert(currentStep.id)
        }
        
        currentIndex += 1
        currentStep = steps[currentIndex]
    }
    
    func previousStep() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        currentStep = steps[currentIndex]
    }
    
    func skipToStep(_ stepId: String) {
        if let index = steps.firstIndex(where: { $0.id == stepId }) {
            currentIndex = index
            currentStep = steps[index]
        }
    }
    
    func endGuide() {
        if let currentStep = currentStep {
            completedSteps.insert(currentStep.id)
        }
        isActive = false
        currentStep = nil
        steps = []
        currentIndex = 0
    }
    
    // MARK: - Persistence Methods
    func saveCompletedSteps() {
        UserDefaults.standard.set(Array(completedSteps), forKey: "CompletedGuideSteps")
    }
    
    func loadCompletedSteps() {
        if let saved = UserDefaults.standard.array(forKey: "CompletedGuideSteps") as? [String] {
            completedSteps = Set(saved)
        }
    }
    
    func shouldShowGuidePrompt(for guideType: GuideType) -> Bool {
        let requiredSteps = guideType.steps.map(\.id)
        return !requiredSteps.allSatisfy { completedSteps.contains($0) }
    }
    
    // MARK: - Computed Properties for GuidePopup
    var currentStepNumber: Int {
        return currentIndex + 1
    }
    
    var totalSteps: Int {
        return steps.count
    }
}

// MARK: - Guide Models
struct GuideStep: Identifiable {
    let id: String
    let title: String
    let description: String
    let targetView: String? // View identifier to highlight
    let position: GuidePosition
    let action: GuideAction?
    let validation: (() -> Bool)?
    
    init(id: String, title: String, description: String, targetView: String? = nil,
         position: GuidePosition = .bottom, action: GuideAction? = nil, validation: (() -> Bool)? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.targetView = targetView
        self.position = position
        self.action = action
        self.validation = validation
    }
}

enum GuidePosition {
    case top, bottom, leading, trailing, center
}

struct GuideAction {
    let title: String
    let action: () -> Void
}

enum GuideType {
    case firstRun
    case recording
    case processing
    case workspace
    
    var steps: [GuideStep] {
        switch self {
        case .firstRun:
            return firstRunSteps
        case .recording:
            return recordingSteps
        case .processing:
            return processingSteps
        case .workspace:
            return workspaceSteps
        }
    }
}

// MARK: - Guide Steps Definitions
private let firstRunSteps: [GuideStep] = [
    GuideStep(
        id: "welcome",
        title: "Welcome to Earprint",
        description: "This guide will walk you through setting up your first workspace and understanding the workflow.",
        position: .center
    ),
    GuideStep(
        id: "workspace_name",
        title: "Name Your Workspace",
        description: "Choose a descriptive name for your workspace. This will help you organize different projects.",
        targetView: "workspace_name_field",
        position: .bottom
    ),
    GuideStep(
        id: "auto_save",
        title: "Auto-Save Settings",
        description: "Enable auto-save to automatically save your processing results. You can change this later in Settings.",
        targetView: "auto_save_toggle",
        position: .bottom
    ),
    GuideStep(
        id: "python_check",
        title: "Python Environment",
        description: "Earprint needs Python for audio processing. We'll verify your environment is ready.",
        targetView: "python_status_card",
        position: .bottom
    ),
    GuideStep(
        id: "workflow_overview",
        title: "Understanding the Workflow",
        description: "Earprint follows a simple process: Record → Process → Export. Let's see how each step works.",
        position: .center
    ),
    GuideStep(
        id: "ready",
        title: "You're Ready!",
        description: "Your workspace is configured. You can access this guide anytime from the Help menu.",
        position: .center
    )
]

private let recordingSteps: [GuideStep] = [
    GuideStep(
        id: "recording_intro",
        title: "Recording Audio",
        description: "This guide will help you set up and perform high-quality recordings for HRIR processing.",
        position: .center
    ),
    GuideStep(
        id: "select_devices",
        title: "Select Audio Devices",
        description: "Choose your input device (microphones) and output device (speakers/headphones) carefully.",
        targetView: "device_selector",
        position: .bottom
    ),
    GuideStep(
        id: "choose_layout",
        title: "Speaker Layout",
        description: "Select the speaker layout that matches your physical setup. This determines the recording sequence.",
        targetView: "layout_selector",
        position: .bottom
    ),
    GuideStep(
        id: "test_signal",
        title: "Test Signal",
        description: "The sweep signal is played through speakers and recorded. Different layouts may use different sweeps.",
        targetView: "test_signal_picker",
        position: .bottom
    ),
    GuideStep(
        id: "positioning",
        title: "Microphone Positioning",
        description: "For HRIR recordings, position binaural microphones in your ears or use a head and torso simulator.",
        position: .center
    ),
    GuideStep(
        id: "start_recording",
        title: "Start Recording",
        description: "Click the record button to begin. Follow any positioning prompts for multi-speaker layouts.",
        targetView: "record_button",
        position: .top
    )
]

private let processingSteps: [GuideStep] = [
    GuideStep(
        id: "processing_intro",
        title: "Processing Recordings",
        description: "Convert your recorded audio into usable HRIR data for spatial audio applications.",
        position: .center
    ),
    GuideStep(
        id: "load_recordings",
        title: "Load Recordings",
        description: "Select the directory containing your recorded WAV files. Earprint will analyze the layout automatically.",
        targetView: "load_button",
        position: .bottom
    ),
    GuideStep(
        id: "processing_settings",
        title: "Processing Settings",
        description: "Adjust settings like target curve, room correction, and output format based on your needs.",
        targetView: "processing_settings",
        position: .bottom
    ),
    GuideStep(
        id: "start_processing",
        title: "Start Processing",
        description: "Begin the processing pipeline. This may take several minutes depending on your recordings.",
        targetView: "process_button",
        position: .top
    ),
    GuideStep(
        id: "export_results",
        title: "Export Results",
        description: "Once processing completes, export your HRIR data in various formats for use with spatial audio tools.",
        targetView: "export_button",
        position: .bottom
    )
]

private let workspaceSteps: [GuideStep] = [
    GuideStep(
        id: "workspace_intro",
        title: "Managing Workspaces",
        description: "Workspaces help organize different projects and measurement sessions.",
        position: .center
    ),
    GuideStep(
        id: "workspace_structure",
        title: "Workspace Structure",
        description: "Each workspace contains recordings, processed data, and project settings in organized folders.",
        position: .center
    ),
    GuideStep(
        id: "switching_workspaces",
        title: "Switching Workspaces",
        description: "Use the workspace selector to switch between different projects.",
        targetView: "workspace_selector",
        position: .bottom
    ),
    GuideStep(
        id: "workspace_settings",
        title: "Workspace Settings",
        description: "Each workspace can have its own processing preferences and default settings.",
        targetView: "workspace_settings",
        position: .bottom
    )
]

// MARK: - Guide Overlay View
struct GuideOverlay: View {
    @ObservedObject var guideManager: GuideManager
    @Namespace private var guideNamespace
    
    var body: some View {
        if guideManager.isActive, let step = guideManager.currentStep {
            ZStack {
                // Semi-transparent background
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                // Highlight target view if specified
                if let targetView = step.targetView {
                    HighlightOverlay(targetView: targetView)
                }
                
                // Guide popup
                GuidePopup(step: step, guideManager: guideManager)
                    .matchedGeometryEffect(id: "guide_popup", in: guideNamespace)
            }
            .transition(.opacity.combined(with: .scale))
            .animation(.easeInOut(duration: 0.3), value: step.id)
        }
    }
}

// MARK: - Highlight Overlay
struct HighlightOverlay: View {
    let targetView: String
    
    var body: some View {
        // Simple highlight overlay - can be enhanced based on actual target positioning
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.blue, lineWidth: 3)
            .background(Color.blue.opacity(0.1))
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: 1)
                    .blur(radius: 2)
            )
    }
}

// MARK: - Guide Popup
struct GuidePopup: View {
    let step: GuideStep
    @ObservedObject var guideManager: GuideManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Step \(currentStepNumber) of \(totalSteps)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("×") {
                    guideManager.endGuide()
                }
                .font(.title2)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }
            
            // Content
            Text(step.description)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            // Action button if specified
            if let action = step.action {
                Button(action.title) {
                    action.action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // Navigation
            HStack {
                Button("Previous") {
                    guideManager.previousStep()
                }
                .disabled(isFirstStep)
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                // Progress indicator
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundColor(index <= currentStepNumber - 1 ? .blue : .gray.opacity(0.3))
                    }
                }
                
                Spacer()
                
                Button(isLastStep ? "Finish" : "Next") {
                    if step.validation?() ?? true {
                        guideManager.nextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10)
        .frame(maxWidth: 350)
        .position(popupPosition)
    }
    
    private var currentStepNumber: Int {
        return guideManager.currentStepNumber
    }
    
    private var totalSteps: Int {
        return guideManager.totalSteps
    }
    
    private var isFirstStep: Bool {
        return currentStepNumber == 1
    }
    
    private var isLastStep: Bool {
        return currentStepNumber == totalSteps
    }
    
    private var popupPosition: CGPoint {
        switch step.position {
        case .center:
            return CGPoint(x: 400, y: 300)
        case .top:
            return CGPoint(x: 400, y: 100)
        case .bottom:
            return CGPoint(x: 400, y: 500)
        case .leading:
            return CGPoint(x: 200, y: 300)
        case .trailing:
            return CGPoint(x: 600, y: 300)
        }
    }
}

// MARK: - View Extensions for Guide Integration
extension View {
    func guideTarget(_ id: String) -> some View {
        self.overlay(
            Color.clear
                .preference(key: GuideTargetPreferenceKey.self, value: [id: .zero])
        )
    }
    
    func withGuide(_ guideManager: GuideManager) -> some View {
        self.overlay(GuideOverlay(guideManager: guideManager))
    }
}

// MARK: - Preference Keys for Guide Positioning
struct GuideTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Menu Commands for Guide Access
struct GuideCommands: Commands {
    @ObservedObject var guideManager: GuideManager
    
    var body: some Commands {
        CommandMenu("Help") {
            Button("Show Setup Guide") {
                guideManager.startGuide(.firstRun)
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
            
            Button("Recording Guide") {
                guideManager.startGuide(.recording)
            }
            
            Button("Processing Guide") {
                guideManager.startGuide(.processing)
            }
            
            Button("Workspace Guide") {
                guideManager.startGuide(.workspace)
            }
            
            Divider()
            
            if guideManager.isActive {
                Button("End Guide") {
                    guideManager.endGuide()
                }
                .keyboardShortcut(.escape)
            }
        }
    }
}
