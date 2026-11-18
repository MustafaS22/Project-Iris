import SwiftUI
import AppKit

enum IrisDesign {
    static let canvas = Color(white: 0.078)
    static let sidebar = Color(white: 0.105)
    static let surface = Color(white: 0.135)
    static let control = Color(white: 0.19)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.97)
    static var secondary: Color { UserDefaults.standard.bool(forKey: "IrisHighContrast") || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? Color(white: 0.88) : Color(red: 0.69, green: 0.69, blue: 0.72) }
    static let blue = Color(red: 0.71, green: 0.84, blue: 1)
}

/// Shared native control styling. SwiftUI keeps keyboard focus and accessibility semantics.
struct IrisActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(primary ? Color(red: 0.06, green: 0.09, blue: 0.15) : IrisDesign.text)
            .background {
                if primary {
                    Capsule().fill(LinearGradient(colors: [.white, IrisDesign.blue], startPoint: .top, endPoint: .bottom))
                } else { Capsule().fill(IrisDesign.control) }
            }
            .overlay(Capsule().strokeBorder(primary ? Color.white.opacity(0.8) : Color.white.opacity(0.16), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

struct IrisGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label.font(.system(size: 17, weight: .semibold))
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).background(LinearGradient(colors: [IrisDesign.surface, IrisDesign.surface.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension IrisTheme {
    func color(customHue: Double = 0.5) -> Color {
        switch self {
        case .apricot: Color(red: 0.91, green: 0.72, blue: 0.54)
        case .sage: Color(red: 0.67, green: 0.76, blue: 0.65)
        case .ice: Color(red: 0.66, green: 0.82, blue: 0.88)
        case .ocean: Color(red: 0.38, green: 0.68, blue: 1)
        case .rose: Color(red: 1, green: 0.57, blue: 0.66)
        case .lilac: Color(red: 0.75, green: 0.63, blue: 1)
        case .sunshine: Color(red: 1, green: 0.83, blue: 0.35)
        case .custom: Color(hue: customHue, saturation: 0.5, brightness: 0.95)
        }
    }
}

/// A static, optically balanced brand mark; animated expressions belong to the assistant face.
struct IrisBrandMark: View {
    var color: Color
    var body: some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 4, height: 7)
            Capsule().fill(color).frame(width: 4, height: 7)
        }.frame(width: 24, height: 24).background(.black, in: RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
    }
}

struct IrisTabBar: View {
    let items: [String]
    @Binding var selection: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { ForEach(items, id: \.self) { item in tab(item) } }
            IrisPicker("Section", selection: $selection, options: items.map { .init(value: $0, title: $0) })
        }.frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }
    private func tab(_ item: String) -> some View {
        Button { selection = item } label: {
            Text(item).font(.system(size: 14, weight: selection == item ? .semibold : .regular)).foregroundStyle(selection == item ? IrisDesign.text : IrisDesign.secondary)
                .padding(.vertical, 14).overlay(alignment: .bottom) { if selection == item { Capsule().fill(IrisDesign.text).frame(height: 2) } }
        }.buttonStyle(.plain).accessibilityAddTraits(selection == item ? .isSelected : [])
    }
}

struct IrisBackdrop: View {
    var accent: Color
    var body: some View {
        LinearGradient(colors: [IrisDesign.canvas, accent.opacity(0.045), IrisDesign.canvas], startPoint: .topLeading, endPoint: .bottomTrailing).background(IrisDesign.canvas)
    }
}


/// An optical weight shared by symbols without altering text or control geometry.
/// Keep the supplied symbol variant: empty/filled states can carry meaning.
private struct IrisSymbolStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.fontWeight(.semibold).symbolRenderingMode(.hierarchical)
    }
}

extension Image {
    func irisSymbolStyle() -> some View { modifier(IrisSymbolStyle()) }
}

/// Read the running bundle, so a development build can never report the website's version by mistake.
struct IrisVersionLabel: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    var body: some View {
        if let version {
            Text(label(for: version))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(IrisDesign.secondary)
                .textSelection(.enabled)
                .help(build.map { "Build \($0)" } ?? "Iris version")
        }
    }

    private func label(for version: String) -> String {
        #if DEBUG
        "Iris \(version) · Debug"
        #else
        "Iris \(version)"
        #endif
    }
}
