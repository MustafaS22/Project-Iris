import SwiftUI

struct OnboardingView: View {
    @ObservedObject var iris: IrisOrchestrator
    var finish: () -> Void
    @State private var step = 0
    @State private var resume = false
    @Environment(\.irisReduceMotion) private var reduceMotion
    init(iris: IrisOrchestrator, startAt: Int = 0, finish: @escaping () -> Void) {
        self.iris = iris; self.finish = finish; _step = State(initialValue: startAt == 1 ? 1 : 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IrisBrandMark(color: iris.accent); Text("Iris").font(.system(size: 19, weight: .bold))
                Spacer()
                Text("AI").foregroundStyle(step == 0 ? IrisDesign.text : iris.accent)
                Image(systemName: "chevron.right").font(.system(size: 9))
                Text("Voice").foregroundStyle(step == 1 ? IrisDesign.text : IrisDesign.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9))
                Text("Meet Iris").foregroundStyle(IrisDesign.secondary)
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(IrisDesign.secondary).padding(.horizontal, 34).padding(.top, 36).padding(.bottom, 26)
            HStack(spacing: 26) {
                IrisAvatar(state: iris.accounts.authorizing ? .thinking : .idle, color: iris.accent, size: 68, animated: true, desktop: true, guidance: iris.preferences.providerVerified ? nil : CGSize(width: 120, height: 100), followsCursorAnywhere: iris.preferences.providerVerified)
                VStack(alignment: .leading, spacing: 10) {
                    Text(step == 0 ? "Let’s make this personal." : "A voice you’ll want to hear.").font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                    Text(step == 0 ? "Connect your AI first. Then we’ll leave this window, meet in the notch, and try something useful for you." : "Choose a voice and try a short preview. I’ll guide you by voice, and you can type at any time.").font(.system(size: 14)).lineSpacing(4).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 34).padding(.bottom, 24)
            Divider().padding(.horizontal, 34)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error = iris.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                    if step == 0 { SourceSettings(iris: iris) }
                    else {
                        VoiceSettingsView(iris: iris)
                        Divider()
                        Text("Voice introduction listens after each question. Answers go to your selected AI. At the end, you decide what Iris remembers.").font(.caption).lineSpacing(3).foregroundStyle(IrisDesign.secondary)
                        if iris.welcome.canResume { Toggle("Pick up where we left off", isOn: $resume).font(.system(size: 13)) }
                    }
                }.padding(34).frame(maxWidth: .infinity, alignment: .leading).id(step).transition(.opacity)
            }
            Divider()
            HStack(spacing: 18) {
                Button(step == 0 ? "I’ll set up later" : "Back") { if step == 0 { finish() } else { step = 0 } }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                Spacer()
                if step == 0 {
                    if iris.preferences.providerVerified { Label("AI ready", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(iris.accent) }
                    Button("Choose my voice", systemImage: "arrow.right") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = 1 } }.buttonStyle(IrisActionStyle(primary: true)).disabled(!iris.preferences.providerVerified || iris.accounts.authorizing)
                } else {
                    Button("I’ll type") { begin(voice: false) }.buttonStyle(IrisActionStyle()).disabled(!iris.preferences.providerVerified)
                    Button("Meet Iris", systemImage: "mic.fill") { begin(voice: true) }.buttonStyle(IrisActionStyle(primary: true)).disabled(!iris.preferences.providerVerified)
                }
            }.padding(24)
        }.frame(minWidth: 820, minHeight: 640).background { WelcomeMaterial(); Color.black.opacity(0.16) }.foregroundStyle(IrisDesign.text).preferredColorScheme(.dark).tint(iris.accent)
            .environment(\.irisControlAccent, iris.accent).textFieldStyle(IrisTextFieldStyle()).groupBoxStyle(IrisGroupStyle()).onAppear { resume = iris.welcome.canResume }
    }
    private func begin(voice: Bool) { guard iris.preferences.providerVerified else { iris.error = "Connect your AI provider first."; step = 0; return }; iris.voice.stop(); iris.voice.stopSpeaking(); iris.welcome.voiceEnabled = voice; iris.welcome.handsFree = voice; iris.beginWelcomeJourney?(resume) }
}
struct IrisPillStyle: ButtonStyle {
    var accent: Color
    func makeBody(configuration: Configuration) -> some View { configuration.label.foregroundStyle(.black).background(LinearGradient(colors: [accent.opacity(0.92), accent], startPoint: .top, endPoint: .bottom), in: Capsule()).opacity(configuration.isPressed ? 0.75 : 1) }
}
