import SwiftUI

enum IrisStyle {
    static let themes = ["Gold", "Sage", "Ocean", "Rose", "Lilac", "Ice"]
    static var accent: Color { color(UserDefaults.standard.string(forKey: "IrisTheme") ?? "Gold") }
    static func color(_ theme: String?) -> Color {
        switch theme {
        case "Sage": Color(red: 0.67, green: 0.79, blue: 0.63)
        case "Ocean": Color(red: 0.35, green: 0.68, blue: 0.90)
        case "Rose": Color(red: 0.93, green: 0.59, blue: 0.66)
        case "Lilac": Color(red: 0.73, green: 0.64, blue: 0.91)
        case "Ice": Color(red: 0.68, green: 0.84, blue: 0.92)
        default: Color(red: 0.91, green: 0.78, blue: 0.43)
        }
    }
    static let background = Color(red: 0.07, green: 0.075, blue: 0.07)
    static let surface = Color(white: 0.13)
}

struct IrisFace: View {
    var size: CGFloat = 70
    var active = false
    var color: Color? = nil
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated || reduceMotion)) { tick in
            let time = tick.date.timeIntervalSinceReferenceDate
            let blink = animated && !reduceMotion && time.truncatingRemainder(dividingBy: 5) < 0.14
            HStack(spacing: size * 0.12) {
                eye(blink: blink)
                eye(blink: blink)
            }
            .frame(width: size, height: size * 0.82)
            .background(.black, in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
            .offset(y: animated && !reduceMotion ? sin(time * 1.4) * 2 : 0)
            .animation(.easeInOut(duration: 0.1), value: blink)
        }.frame(width: size, height: size * 0.9)
            .accessibilityLabel(active ? "Iris is working" : "Iris")
    }
    private func eye(blink: Bool) -> some View {
        Capsule().fill(color ?? IrisStyle.accent)
            .frame(width: size * 0.11, height: blink ? size * 0.025 : size * 0.22)
    }
}
