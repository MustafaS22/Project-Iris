import SwiftUI
struct WelcomeConversationView: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var journey: WelcomeJourney
    var body: some View { WelcomeCoachView(iris: iris, journey: journey) }
}
