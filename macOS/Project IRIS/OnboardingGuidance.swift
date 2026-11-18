import Foundation

/// Guidance is based on real setup state; optional steps can be explicitly accepted or deferred.
struct OnboardingGuidance: Equatable {
    enum Target: String { case preview, name, themes, intelligence, knowledge, tour, error }
    let title: String
    let detail: String
    let target: Target?
    let acceptLabel: String?

    static func resolve(step: Int, accepted: Bool, hasName: Bool, aiReady: Bool, hasKnowledge: Bool, working: Bool, hasError: Bool) -> Self {
        if hasError { return .init(title: "Let's sort this out.", detail: "The message on the right explains what needs attention. You can dismiss it and continue.", target: .error, acceptLabel: nil) }
        if working { return .init(title: "Connecting your world…", detail: "Finish the sign-in or import. I'll stay here while it completes.", target: step == 4 ? .knowledge : .intelligence, acceptLabel: nil) }
        let complete = accepted || (step == 1 && hasName) || (step == 3 && aiReady) || (step == 4 && hasKnowledge)
        if complete { return .init(title: step == 5 ? "We're ready." : "Looking good.", detail: step == 5 ? "Open Iris whenever you're ready. I'm here to help." : "This step is ready. Keep exploring, or continue when you like.", target: nil, acceptLabel: nil) }
        switch step {
        case 0: return .init(title: "Hi, I'm Iris.", detail: "Try the listening preview. It's a demo, so your microphone stays off.", target: .preview, acceptLabel: "Skip the demo")
        case 1: return .init(title: "What should I call you?", detail: "Add your name. Your role and interests are optional, and you can change them later.", target: .name, acceptLabel: "I'll personalize later")
        case 2: return .init(title: "Find your color.", detail: "Choose a preview to see my new look. Listening and access options are below.", target: .themes, acceptLabel: "Keep this color")
        case 3: return .init(title: "Choose how I think.", detail: "Connect an AI account or a local model. You can also finish this in Settings.", target: .intelligence, acceptLabel: "Set up AI later")
        case 4: return .init(title: "Bring what matters.", detail: "Connect a source if you'd like me to use your material. Every source is optional.", target: .knowledge, acceptLabel: "Continue without sources")
        default: return .init(title: "One last look.", detail: "Try opening the notch preview. Then choose where you'd like to start.", target: .tour, acceptLabel: "I'm ready")
        }
    }
}
