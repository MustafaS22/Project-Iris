import AppKit
import Combine
import SwiftUI

enum IrisMenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case eyes, face, orbit, spark, bloom, pulse
    var id: String { rawValue }
    var title: String {
        switch self { case .eyes: "Iris Eyes"; case .face: "Mini Iris"; case .orbit: "Orbit"; case .spark: "Spark"; case .bloom: "Bloom"; case .pulse: "Pulse" }
    }
    // Template artwork uses alpha, so macOS supplies the correct menu-bar color.
    @MainActor var image: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill(); NSColor.black.setStroke()
            func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: w / 2, yRadius: w / 2).fill()
            }
            switch self {
            case .eyes:
                pill(3, 4, 4, 10); pill(11, 4, 4, 10)
            case .face:
                let face = NSBezierPath(roundedRect: NSRect(x: 1, y: 1.5, width: 16, height: 15), xRadius: 5, yRadius: 5)
                face.lineWidth = 1.6; face.stroke()
                pill(5, 6, 2.5, 6); pill(10.5, 6, 2.5, 6)
            case .orbit:
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform(); t.translateX(by: 9, yBy: 9); t.rotate(byDegrees: 28); t.concat()
                let ring = NSBezierPath(ovalIn: NSRect(x: -8, y: -3.2, width: 16, height: 6.4))
                ring.lineWidth = 1.6; ring.stroke()
                NSGraphicsContext.restoreGraphicsState()
                NSBezierPath(ovalIn: NSRect(x: 5.5, y: 5.5, width: 7, height: 7)).fill()
                NSBezierPath(ovalIn: NSRect(x: 13, y: 12.5, width: 3.2, height: 3.2)).fill()
            case .spark:
                let star = NSBezierPath()
                star.move(to: NSPoint(x: 9, y: 17))
                star.curve(to: NSPoint(x: 17, y: 9), controlPoint1: NSPoint(x: 10.5, y: 11), controlPoint2: NSPoint(x: 11, y: 10.5))
                star.curve(to: NSPoint(x: 9, y: 1), controlPoint1: NSPoint(x: 11, y: 7.5), controlPoint2: NSPoint(x: 10.5, y: 7))
                star.curve(to: NSPoint(x: 1, y: 9), controlPoint1: NSPoint(x: 7.5, y: 7), controlPoint2: NSPoint(x: 7, y: 7.5))
                star.curve(to: NSPoint(x: 9, y: 17), controlPoint1: NSPoint(x: 7, y: 10.5), controlPoint2: NSPoint(x: 7.5, y: 11))
                star.close(); star.fill()
            case .bloom:
                for i in 0..<6 {
                    let angle = Double(i) * .pi / 3
                    let x = 9 + cos(angle) * 5, y = 9 + sin(angle) * 5
                    NSBezierPath(ovalIn: NSRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)).fill()
                }
                NSBezierPath(ovalIn: NSRect(x: 6.5, y: 6.5, width: 5, height: 5)).fill()
            case .pulse:
                pill(1.5, 6, 2.5, 6); pill(5.5, 3, 2.5, 12)
                pill(9.5, 1, 2.5, 16); pill(13.5, 5, 2.5, 8)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class IrisMenuBarIcons: ObservableObject {
    static let shared = IrisMenuBarIcons()
    private static let key = "Iris.menuBarIcon.v1"
    private let defaults: UserDefaults
    @Published private(set) var selection: IrisMenuBarStyle
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: Self.key).flatMap(IrisMenuBarStyle.init(rawValue:)) ?? .eyes
    }
    func select(_ style: IrisMenuBarStyle) {
        selection = style
        defaults.set(style.rawValue, forKey: Self.key)
    }
}

struct IrisMenuBarIconSettings: View {
    let accent: Color
    @ObservedObject private var icons = IrisMenuBarIcons.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A little Iris, always nearby").font(.system(size: 20, weight: .semibold))
                Text("Choose the symbol at the top of your Mac. Changes appear immediately.")
                    .font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
            }
            HStack(spacing: 16) {
                menuPreview(light: false)
                menuPreview(light: true)
            }.accessibilityElement(children: .ignore).accessibilityLabel("\(icons.selection.title) preview in dark and light menu bars")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 100), spacing: 12), count: 3), spacing: 12) {
                ForEach(IrisMenuBarStyle.allCases) { style in
                    Button { icons.select(style) } label: {
                        VStack(spacing: 14) {
                            Image(nsImage: style.image).renderingMode(.template).resizable().scaledToFit().frame(width: 25, height: 25)
                            Text(style.title).font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .foregroundStyle(icons.selection == style ? accent : IrisDesign.text)
                        .background(icons.selection == style ? accent.opacity(0.075) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(icons.selection == style ? accent.opacity(0.8) : .white.opacity(0.09), lineWidth: icons.selection == style ? 1.5 : 1))
                        .overlay(alignment: .topTrailing) {
                            if icons.selection == style { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).padding(10) }
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(style.title) menu-bar icon").accessibilityAddTraits(icons.selection == style ? .isSelected : [])
                }
            }
            Label("Matches light and dark menu bars automatically. Your app icon stays independent.", systemImage: "circle.lefthalf.filled")
                .font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
        }
    }
    private func menuPreview(light: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("Iris").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 8)
                Image(nsImage: icons.selection.image).renderingMode(.template).frame(width: 18, height: 18)
                Image(systemName: "wifi").font(.system(size: 11, weight: .medium))
                Text("12:34").font(.system(size: 11, weight: .medium)).monospacedDigit()
            }.foregroundStyle(light ? Color.black.opacity(0.85) : .white.opacity(0.9))
                .padding(.horizontal, 15).padding(.vertical, 14)
                .background(light ? Color(white: 0.9) : Color(white: 0.17), in: RoundedRectangle(cornerRadius: 11))
            Text(light ? "Light menu bar" : "Dark menu bar").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary)
        }
    }
}
