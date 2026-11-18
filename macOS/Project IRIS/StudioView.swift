import SwiftUI

/// A focused home for existing study material. New tasks start in the shared chat.
struct StudioView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var practice = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Button { iris.workspaceSection = .library } label: { Label("Library", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary)
                Spacer()
                Button(practice ? "Study spaces" : "Practice saved cards") { practice.toggle() }.buttonStyle(IrisActionStyle())
            }
            if practice { StudyWorkbench(iris: iris) }
            else { StudentNotebooksView(iris: iris, session: iris.notebookSession) }
        }
    }
}
