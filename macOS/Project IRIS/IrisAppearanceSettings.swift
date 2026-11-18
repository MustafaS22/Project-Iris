import SwiftUI

struct IrisAppearanceSettings: View {
    @ObservedObject var iris: IrisOrchestrator
    @AppStorage("Iris.appearancePage.v1") private var page = "Colors"
    private let pages = ["Colors", "App icon", "Menu bar"]
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 16) {
                IrisAvatar(state: .idle, color: iris.accent, size: 54)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your Iris, your way.").font(.system(size: 19, weight: .semibold))
                    Text("A few personal touches. Still unmistakably Iris.").font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                }
                Spacer(minLength: 8)
                IrisFormField(title: "Your name", prompt: "What should I call you?", text: Binding(get: { iris.preferences.name }, set: { value in iris.setPreference { $0.name = value } })).frame(maxWidth: 210)
            }.padding(.bottom, 2)
            IrisTabBar(items: pages, selection: $page)
            Group {
                switch page {
                case "App icon": IrisIconSettings(accent: iris.accent)
                case "Menu bar": IrisMenuBarIconSettings(accent: iris.accent)
                default: colors
                }
            }
            Label("Iris respects your Mac’s Reduce Motion setting.", systemImage: "accessibility")
                .font(.system(size: 11)).foregroundStyle(IrisDesign.secondary.opacity(0.8)).padding(.top, 4)
        }
    }
    private var colors: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set the mood").font(.system(size: 20, weight: .semibold))
                Text("See how each color feels in your notch and chat before choosing it.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 156, maximum: 240), spacing: 12)], spacing: 12) {
                ForEach(IrisTheme.allCases, id: \.self) { theme in
                    IrisOnboardingThemeTile(theme: theme, hue: iris.preferences.customHue ?? 0.5, selected: iris.preferences.theme == theme) {
                        iris.setPreference { $0.theme = theme }
                    }
                }
            }
            HStack(spacing: 16) {
                Circle().fill(IrisTheme.custom.color(customHue: iris.preferences.customHue ?? 0.5)).frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find your own color").font(.system(size: 12, weight: .semibold))
                    Text("Move the slider to switch to Custom.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
                }
                Slider(value: Binding(get: { iris.preferences.customHue ?? 0.5 }, set: { value in iris.setPreference { $0.customHue = value; $0.theme = .custom } }), in: 0...1)
                    .tint(iris.accent).accessibilityLabel("Custom accent hue").frame(minWidth: 100)
            }.padding(16).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
        }
    }
}
