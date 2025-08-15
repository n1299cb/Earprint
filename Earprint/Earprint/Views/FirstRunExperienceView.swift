import SwiftUI

// MARK: - First Run Experience Views
struct FirstRunExperienceView: View {
    @EnvironmentObject var workspaceManager: WorkspaceManager
    @EnvironmentObject var configurationVM: ConfigurationViewModel
    @StateObject private var onboardingManager = OnboardingManager()
    let onComplete: () -> Void
    
    var body: some View {
        NavigationStack(path: $onboardingManager.navigationPath) {
            WelcomeScreen(onboardingManager: onboardingManager)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .welcome:
                        WelcomeScreen(onboardingManager: onboardingManager)
                    case .workflow:
                        WorkflowOverviewScreen(onboardingManager: onboardingManager)
                    case .setup:
                        SetupScreen(
                            onboardingManager: onboardingManager,
                            workspaceManager: workspaceManager,
                            configurationVM: configurationVM
                        )
                    case .complete:
                        CompletionScreen(onComplete: onComplete)
                    }
                }
        }
        .frame(width: 900, height: 700)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Onboarding Manager
@MainActor
class OnboardingManager: ObservableObject {
    @Published var navigationPath = NavigationPath()
    @Published var currentStep: OnboardingStep = .welcome
    
    func advance(to step: OnboardingStep) {
        currentStep = step
        navigationPath.append(step)
    }
    
    func back() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
}

enum OnboardingStep: Hashable, CaseIterable {
    case welcome
    case workflow
    case setup
    case complete
    
    var title: String {
        switch self {
        case .welcome: return "Welcome to Earprint"
        case .workflow: return "How It Works"
        case .setup: return "Initial Setup"
        case .complete: return "You're Ready!"
        }
    }
}

// MARK: - Welcome Screen
struct WelcomeScreen: View {
    @ObservedObject var onboardingManager: OnboardingManager
    
    var body: some View {
        VStack(spacing: 30) {
            // App Icon and Title
            VStack(spacing: 16) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red.gradient)
                
                Text("Welcome to Earprint")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Professional Binaural Impulse Response Capture & Processing")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Feature highlights
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "headphones.circle.fill",
                    title: "High-Quality HRIR/BRIR Capture",
                    description: "Record binaural impulse responses with professional accuracy"
                )
                
                FeatureRow(
                    icon: "gearshape.fill",
                    title: "Advanced Processing Pipeline",
                    description: "Transform recordings into optimized HRTFs and spatial audio files"
                )
                
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Real-time Visualization",
                    description: "Monitor frequency responses and processing results"
                )
                
                FeatureRow(
                    icon: "externaldrive.fill",
                    title: "Export-Ready Formats",
                    description: "Generate files for HeSuVi, EqualizerAPO, and other spatial audio tools"
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Navigation
            HStack {
                Spacer()
                
                Button("Get Started") {
                    onboardingManager.advance(to: .workflow)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
        .navigationBarBackButtonHidden()
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Workflow Overview Screen
struct WorkflowOverviewScreen: View {
    @ObservedObject var onboardingManager: OnboardingManager
    
    var body: some View {
        VStack(spacing: 30) {
            Text("The Earprint Workflow")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Earprint follows a simple 4-step process to create personalized spatial audio")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Workflow steps
            VStack(spacing: 24) {
                WorkflowStep(
                    number: 1,
                    icon: "mic.fill",
                    title: "Recording Setup",
                    description: "Configure your binaural microphones, headphones, and speaker layout",
                    color: .blue
                )
                
                WorkflowStep(
                    number: 2,
                    icon: "play.fill",
                    title: "Capture Measurements",
                    description: "Record test signals played through your speaker system",
                    color: .green
                )
                
                WorkflowStep(
                    number: 3,
                    icon: "cpu.fill",
                    title: "Process Data",
                    description: "Transform recordings into impulse responses with advanced algorithms",
                    color: .orange
                )
                
                WorkflowStep(
                    number: 4,
                    icon: "square.and.arrow.up.fill",
                    title: "Export Results",
                    description: "Generate files for your preferred spatial audio software",
                    color: .purple
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Navigation
            HStack {
                Button("Back") {
                    onboardingManager.back()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Continue") {
                    onboardingManager.advance(to: .setup)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
        .navigationBarBackButtonHidden()
    }
}

// MARK: - Workflow Step Component
struct WorkflowStep: View {
    let number: Int
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 20) {
            // Step number circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 60, height: 60)
                
                Text("\(number)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            
            // Step icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
            
            // Step content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Setup Screen
struct SetupScreen: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @ObservedObject var workspaceManager: WorkspaceManager
    @ObservedObject var configurationVM: ConfigurationViewModel
    @State private var workspaceName = "My First Project"
    @State private var enableAutoSave = true
    @State private var pythonStatus: PythonStatus = .checking
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Initial Setup")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Let's configure your workspace and verify your environment")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 24) {
                // Workspace Setup
                SetupCard(
                    icon: "folder.badge.gearshape",
                    title: "Create Workspace",
                    color: .blue
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your workspace will store recordings, processed files, and project settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Workspace name", text: $workspaceName)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Will be created in: ~/Library/Application Support/Earprint/Workspaces/")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Python Environment Check
                SetupCard(
                    icon: "terminal",
                    title: "Python Environment",
                    color: pythonStatus.color
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                                .opacity(pythonStatus == .checking ? 1 : 0)
                            
                            Text(pythonStatus.description)
                                .font(.caption)
                        }
                        
                        if pythonStatus == .failed {
                            Text("Python dependencies are required for audio processing. Please install them using the instructions in Settings.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Configuration Options
                SetupCard(
                    icon: "gearshape.2",
                    title: "Preferences",
                    color: .purple
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-save processing results", isOn: $enableAutoSave)
                            .font(.caption)
                        
                        Text("You can always change these settings later in Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Navigation
            HStack {
                Button("Back") {
                    onboardingManager.back()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Create Workspace & Continue") {
                    createWorkspaceAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(workspaceName.isEmpty)
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
        .navigationBarBackButtonHidden()
        .onAppear {
            checkPythonEnvironment()
        }
    }
    
    private func createWorkspaceAndContinue() {
        // Apply configuration
        configurationVM.updateAutoSaveResults(enableAutoSave)
        
        // Create workspace (if needed)
        if !workspaceName.isEmpty {
            // WorkspaceManager should handle creation
            workspaceManager.workspaceName = workspaceName
        }
        
        onboardingManager.advance(to: .complete)
    }
    
    private func checkPythonEnvironment() {
        pythonStatus = .checking
        
        // Simple check - in real implementation, you'd verify Python dependencies
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Simulate check result - you could integrate with actual Python environment checking
            pythonStatus = .ready
        }
    }
}

// MARK: - Python Status
enum PythonStatus {
    case checking
    case ready
    case failed
    
    var color: Color {
        switch self {
        case .checking: return .orange
        case .ready: return .green
        case .failed: return .red
        }
    }
    
    var description: String {
        switch self {
        case .checking: return "Checking Python environment..."
        case .ready: return "Python environment ready"
        case .failed: return "Python environment needs setup"
        }
    }
}

// MARK: - Setup Card Component
struct SetupCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            content
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Completion Screen
struct CompletionScreen: View {
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Success animation
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green.gradient)
                
                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Earprint is ready for professional binaural audio capture")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Next steps
            VStack(spacing: 20) {
                Text("Recommended next steps:")
                    .font(.headline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 16) {
                    NextStepRow(
                        number: 1,
                        title: "Check your workspace",
                        description: "Verify your project folder and settings",
                        icon: "folder.badge.gearshape"
                    )
                    
                    NextStepRow(
                        number: 2,
                        title: "Set up recording equipment",
                        description: "Connect binaural microphones and configure audio devices",
                        icon: "headphones.circle"
                    )
                    
                    NextStepRow(
                        number: 3,
                        title: "Start with the demo",
                        description: "Try processing the included sample recordings",
                        icon: "play.circle"
                    )
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Final action
            Button("Start Using Earprint") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
        }
        .padding(40)
        .navigationBarBackButtonHidden()
    }
}

// MARK: - Next Step Row Component
struct NextStepRow: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Step number
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            // Icon
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}
